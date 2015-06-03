# name: discourse-tagging
# about: Support for tagging topics in Discourse
# version: 0.1
# authors: Robin Ward
# url: https://github.com/discourse/discourse-tagging

enabled_site_setting :tagging_enabled
register_asset 'stylesheets/tagging.scss'

after_initialize do

  TAGS_FIELD_NAME = "tags"
  TAGS_FILTER_REGEXP = /[<\\\/\>\#\?\&\s]/

  module ::DiscourseTagging
    class Engine < ::Rails::Engine
      engine_name "discourse_tagging"
      isolate_namespace DiscourseTagging
    end

    def self.clean_tag(tag)
      tag.downcase.strip[0...SiteSetting.max_tag_length].gsub(TAGS_FILTER_REGEXP, '')
    end

    def self.tags_for_saving(tags, guardian)
      return unless tags

      tags.map! {|t| clean_tag(t) }
      tags.delete_if {|t| t.blank? }
      tags.uniq!

      # If the user can't create tags, remove any tags that don't already exist
      unless guardian.can_create_tag?
        tag_count = TopicCustomField.where(name: TAGS_FIELD_NAME, value: tags).group(:value).count
        tags.delete_if {|t| !tag_count.has_key?(t) }
      end

      return tags[0...SiteSetting.max_tags_per_topic]
    end

    def self.notification_key(tag_id)
      "tags_notification:#{tag_id}"
    end

    def self.auto_notify_for(tags, topic)

      key_names = tags.map {|t| notification_key(t) }
      key_names_sql = ActiveRecord::Base.sql_fragment("(#{tags.map { "'%s'" }.join(', ')})", *key_names)

      sql = <<-SQL
         INSERT INTO topic_users(user_id, topic_id, notification_level, notifications_reason_id)
         SELECT ucf.user_id,
                #{topic.id.to_i},
                CAST(ucf.value AS INTEGER),
                #{TopicUser.notification_reasons[:plugin_changed]}
         FROM user_custom_fields AS ucf
         WHERE ucf.name IN #{key_names_sql}
           AND NOT EXISTS(SELECT 1 FROM topic_users WHERE topic_id = #{topic.id.to_i} AND user_id = ucf.user_id)
           AND CAST(ucf.value AS INTEGER) <> #{TopicUser.notification_levels[:regular]}
      SQL

      ActiveRecord::Base.exec_sql(sql)
    end

    def self.rename_tag(current_user, old_id, new_id)
      sql = <<-SQL
        UPDATE topic_custom_fields AS tcf
          SET value = :new_id
        WHERE value = :old_id
          AND name = :tags_field_name
          AND NOT EXISTS(SELECT 1
                         FROM topic_custom_fields
                         WHERE value = :new_id AND name = :tags_field_name AND topic_id = tcf.topic_id)
      SQL

      user_sql = <<-SQL
        UPDATE user_custom_fields
          SET name = :new_user_tag_id
        WHERE name = :old_user_tag_id
          AND NOT EXISTS(SELECT 1
                         FROM user_custom_fields
                         WHERE name = :new_user_tag_id)
      SQL

      ActiveRecord::Base.transaction do
        ActiveRecord::Base.exec_sql(sql, new_id: new_id, old_id: old_id, tags_field_name: TAGS_FIELD_NAME)
        TopicCustomField.delete_all(name: TAGS_FIELD_NAME, value: old_id)
        ActiveRecord::Base.exec_sql(user_sql, new_user_tag_id: notification_key(new_id),
                                         old_user_tag_id: notification_key(old_id))
        UserCustomField.delete_all(name: notification_key(old_id))
        StaffActionLogger.new(current_user).log_custom('renamed_tag', previous_value: old_id, new_value: new_id)
      end
    end
  end

  require_dependency 'application_controller'
  require_dependency 'topic_list_responder'
  require_dependency 'topics_bulk_action'
  class DiscourseTagging::TagsController < ::ApplicationController
    include ::TopicListResponder

    requires_plugin 'discourse-tagging'
    skip_before_filter :check_xhr, only: [:tag_feed, :show]
    before_filter :ensure_logged_in, only: [:notifications, :update_notifications, :update]

    def index
      tag_counts = self.class.tags_by_count(guardian, limit: 300).count
      tags = tag_counts.map {|t, c| { id: t, text: t, count: c } }
      render json: { tags: tags }
    end

    def show
      tag_id = ::DiscourseTagging.clean_tag(params[:tag_id])
      topics_tagged = TopicCustomField.where(name: TAGS_FIELD_NAME, value: tag_id).pluck(:topic_id)

      page = params[:page].to_i

      query = TopicQuery.new(current_user, page: page)
      latest_results = query.latest_results.where(id: topics_tagged)
      @list = query.create_list(:by_tag, {}, latest_results)
      @list.more_topics_url = list_by_tag_path(tag_id: tag_id, page: page + 1)
      @rss = "tag"

      respond_with_list(@list)
    end

    def update
      guardian.ensure_can_admin_tags!

      new_tag_id = ::DiscourseTagging.clean_tag(params[:tag][:id])
      if current_user.staff?
        ::DiscourseTagging.rename_tag(current_user, params[:tag_id], new_tag_id)
      end
      render json: { tag: { id: new_tag_id }}
    end

    def destroy
      guardian.ensure_can_admin_tags!
      tag_id = params[:tag_id]
      TopicCustomField.transaction do
        TopicCustomField.where(name: TAGS_FIELD_NAME, value: tag_id).delete_all
        UserCustomField.delete_all(name: ::DiscourseTagging.notification_key(tag_id))
        StaffActionLogger.new(current_user).log_custom('deleted_tag', subject: tag_id)
      end
      render json: success_json
    end

    def tag_feed
      discourse_expires_in 1.minute

      tag_id = ::DiscourseTagging.clean_tag(params[:tag_id])
      @link = "#{Discourse.base_url}/tags/#{tag_id}"
      @description = I18n.t("rss_by_tag", tag: tag_id)
      @title = "#{SiteSetting.title} - #{@description}"
      @atom_link = "#{Discourse.base_url}/tags/#{tag_id}.rss"

      query = TopicQuery.new(current_user)
      topics_tagged = TopicCustomField.where(name: TAGS_FIELD_NAME, value: tag_id).pluck(:topic_id)
      latest_results = query.latest_results.where(id: topics_tagged)
      @topic_list = query.create_list(:by_tag, {}, latest_results)

      render 'list/list', formats: [:rss]
    end

    def search
      tags = self.class.tags_by_count(guardian)
      term = params[:q]
      if term.present?
        term.gsub!(/[^a-z0-9\.\-]*/, '')
        tags = tags.where('value like ?', "%#{term}%")
      end

      tags = tags.count(:value).map {|t, c| { id: t, text: t, count: c } }

      render json: { results: tags }
    end

    def notifications
      level = current_user.custom_fields[::DiscourseTagging.notification_key(params[:tag_id])] || 1
      render json: { tag_notification: { id: params[:tag_id], notification_level: level.to_i } }
    end

    def update_notifications
      level = params[:tag_notification][:notification_level].to_i

      current_user.custom_fields[::DiscourseTagging.notification_key(params[:tag_id])] = level
      current_user.save_custom_fields

      render json: {notification_level: level}
    end

    private

      def self.tags_by_count(guardian, opts=nil)
        opts = opts || {}
        result = TopicCustomField.where(name: TAGS_FIELD_NAME)
                                 .joins(:topic)
                                 .group(:value)
                                 .limit(opts[:limit] || 5)
                                 .order('COUNT(topic_custom_fields.value) DESC')

        guardian.filter_allowed_categories(result)
      end
  end

  DiscourseTagging::Engine.routes.draw do
    get '/' => 'tags#index'
    get '/filter/list' => 'tags#index'
    get '/filter/search' => 'tags#search'
    constraints(tag_id: /[^\/]+?/, format: /json|rss/) do
        get '/:tag_id.rss' => 'tags#tag_feed'
        get '/:tag_id' => 'tags#show', as: 'list_by_tag'
        get '/:tag_id/notifications' => 'tags#notifications'
        put '/:tag_id/notifications' => 'tags#update_notifications'
        put '/:tag_id' => 'tags#update'
        delete '/:tag_id' => 'tags#destroy'
    end
  end

  Discourse::Application.routes.append do
    mount ::DiscourseTagging::Engine, at: "/tags"
  end

  # Add a `tags` reader to the Topic model for easy reading of tags
  add_to_class(:topic, :tags) do
    result = custom_fields[TAGS_FIELD_NAME]
    return [result].flatten if result
  end

  # Save the tags when the topic is saved
  PostRevisor.track_topic_field(:tags_empty_array) do |tc, val|
    if val.present?
      tc.record_change(TAGS_FIELD_NAME, tc.topic.custom_fields[TAGS_FIELD_NAME], nil)
      tc.topic.custom_fields.delete(TAGS_FIELD_NAME)
    end
  end

  PostRevisor.track_topic_field(:tags) do |tc, tags|
    if tags.present?
      tags = ::DiscourseTagging.tags_for_saving(tags, tc.guardian)

      new_tags = tags - (tc.topic.tags || [])
      tc.record_change(TAGS_FIELD_NAME, tc.topic.custom_fields[TAGS_FIELD_NAME], tags)
      tc.topic.custom_fields.update(TAGS_FIELD_NAME => tags)

      ::DiscourseTagging.auto_notify_for(new_tags, tc.topic) if new_tags.present?
    end
  end

  on(:topic_created) do |topic, params, user|
    tags = ::DiscourseTagging.tags_for_saving(params[:tags], Guardian.new(user))
    if tags.present?
      topic.custom_fields.update(TAGS_FIELD_NAME => tags)
      topic.save
      ::DiscourseTagging.auto_notify_for(tags, topic)
    end
  end

  add_to_class(:guardian, :can_create_tag?) do
    user && user.has_trust_level?(SiteSetting.min_trust_to_create_tag.to_i)
  end

  add_to_class(:guardian, :can_admin_tags?) do
    user.try(:staff?)
  end

  TopicsBulkAction.register_operation('change_tags') do
    tags = @operation[:tags]
    tags = ::DiscourseTagging.tags_for_saving(tags, guardian) if tags.present?

    topics.each do |t|
      if guardian.can_edit?(t)
        if tags.present?
          t.custom_fields.update(TAGS_FIELD_NAME => tags)
          t.save
          ::DiscourseTagging.auto_notify_for(tags, t)
        else
          t.custom_fields.delete(TAGS_FIELD_NAME)
        end
      end
    end
  end

  # Return tag related stuff in JSON output
  TopicViewSerializer.attributes_from_topic(:tags)
  add_to_serializer(:site, :can_create_tag) { scope.can_create_tag? }
  add_to_serializer(:site, :tags_filter_regexp) { TAGS_FILTER_REGEXP.source }

  Plugin::Filter.register(:topic_categories_breadcrumb) do |topic, breadcrumbs|
    if (tags = topic.tags).present?
      tags.each do |tag|
        tag_id = ::DiscourseTagging.clean_tag(tag)
        url = "#{Discourse.base_url}/tags/#{tag_id}"
        breadcrumbs << {url: url, name: tag}
      end
    end
    breadcrumbs
  end

end
