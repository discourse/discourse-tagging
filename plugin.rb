# name: discourse-tagging
# about: Support for tagging topics in Discourse
# version: 0.2
# authors: Robin Ward
# url: https://github.com/discourse/discourse-tagging

enabled_site_setting :tagging_enabled
register_asset 'stylesheets/tagging.scss'

after_initialize do

  if SiteSetting.respond_to?(:supported_types) && SiteSetting.supported_types.include?(:enum)
    SiteSetting.client_setting("tag_style", "simple",
                                  type: "enum",
                                  choices: ["simple", "bullet","box"],
                                  preview: '
  <div class="discourse-tags">
    <span class="discourse-tag {{value}}">tag1</span>
    <span class="discourse-tag {{value}}">tag2</span>
  </div>',
                                  category: "plugins"
                              )
  end


  TAGS_FIELD_NAME = "tags"
  TAGS_FILTER_REGEXP = /[<\\\/\>\#\?\&\s]/

  module ::DiscourseTagging
    TAGS_FIELD_NAME = "tags"

    class Engine < ::Rails::Engine
      engine_name "discourse_tagging"
      isolate_namespace DiscourseTagging
    end

    def self.clean_tag(tag)
      tag.downcase.strip[0...SiteSetting.max_tag_length].gsub(TAGS_FILTER_REGEXP, '')
    end

    def self.staff_only_tags(tags)
      return nil if tags.nil?

      staff_tags = SiteSetting.staff_tags.split("|")

      tag_diff = tags - staff_tags
      tag_diff = tags - tag_diff

      tag_diff.present? ? tag_diff : nil
    end

    def self.tags_for_saving(tags, guardian)

      return [] unless guardian.can_tag_topics?

      return unless tags

      tags.map! {|t| clean_tag(t) }
      tags.delete_if {|t| t.blank? }
      tags.uniq!

      # If the user can't create tags, remove any tags that don't already exist
      # TODO: this is doing a full count, it should just check first or use a cache
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
      # This insert will run up to SiteSetting.max_tags_per_topic times
      tags.each do |tag|
        key_name_sql = ActiveRecord::Base.sql_fragment("('#{notification_key(tag)}')", tag)

        sql = <<-SQL
           INSERT INTO topic_users(user_id, topic_id, notification_level, notifications_reason_id)
           SELECT ucf.user_id,
                  #{topic.id.to_i},
                  CAST(ucf.value AS INTEGER),
                  #{TopicUser.notification_reasons[:plugin_changed]}
           FROM user_custom_fields AS ucf
           WHERE ucf.name IN #{key_name_sql}
             AND NOT EXISTS(SELECT 1 FROM topic_users WHERE topic_id = #{topic.id.to_i} AND user_id = ucf.user_id)
             AND CAST(ucf.value AS INTEGER) <> #{TopicUser.notification_levels[:regular]}
        SQL

        ActiveRecord::Base.exec_sql(sql)
      end
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

    def self.top_tags(limit_arg=nil)
      # TODO: cache
      # TODO: need an index for this (name,value)
      TopicCustomField.where(name: TAGS_FIELD_NAME)
                      .group(:value)
                      .limit(limit_arg || SiteSetting.max_tags_in_filter_list)
                      .order('COUNT(value) DESC')
                      .count
                      .map {|name, count| name}
    end

    def self.muted_tags(user)
      return [] unless user
      UserCustomField.where(user_id: user.id, value: TopicUser.notification_levels[:muted]).pluck(:name).map { |x| x[0,17] == "tags_notification" ? x[18..-1] : nil}.compact
    end
  end

  require_dependency 'application_controller'
  require_dependency 'topic_list_responder'
  require_dependency 'topics_bulk_action'
  require_dependency 'topic_query'

  class DiscourseTagging::TagsController < ::ApplicationController
    include ::TopicListResponder

    requires_plugin 'discourse-tagging'
    skip_before_filter :check_xhr, only: [:tag_feed, :show]
    before_filter :ensure_logged_in, only: [:notifications, :update_notifications, :update]
    before_filter :set_category_from_params, except: [:index, :update, :destroy, :tag_feed, :search, :notifications, :update_notifications]

    def index
      tag_counts = self.class.tags_by_count(guardian, limit: 300).count
      tags = tag_counts.map {|t, c| { id: t, text: t, count: c } }
      render json: { tags: tags }
    end

    Discourse.filters.each do |filter|
      define_method("show_#{filter}") do
        @tag_id = ::DiscourseTagging.clean_tag(params[:tag_id])

        # TODO PERF: doesn't scale:
        topics_tagged = TopicCustomField.where(name: TAGS_FIELD_NAME, value: @tag_id).pluck(:topic_id)

        page = params[:page].to_i

        query = TopicQuery.new(current_user, build_topic_list_options)

        results = query.send("#{filter}_results").where(id: topics_tagged)

        if @filter_on_category
          category_ids = [@filter_on_category.id] + @filter_on_category.subcategories.pluck(:id)
          results = results.where(category_id: category_ids)
        end

        @list = query.create_list(:by_tag, {}, results)

        @list.draft_key = Draft::NEW_TOPIC
        @list.draft_sequence = DraftSequence.current(current_user, Draft::NEW_TOPIC)
        @list.draft = Draft.get(current_user, @list.draft_key, @list.draft_sequence) if current_user

        @list.more_topics_url = list_by_tag_path(tag_id: @tag_id, page: page + 1)
        @rss = "tag"


        if @list.topics.size == 0 && !TopicCustomField.where(name: TAGS_FIELD_NAME, value: @tag_id).exists?
          raise Discourse::NotFound
        else
          respond_with_list(@list)
        end
      end
    end

    def show
      show_latest
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
      tags = self.class.tags_by_count(guardian, params.slice(:limit))
      term = params[:q]
      if term.present?
        term.gsub!(/[^a-z0-9\.\-\_]*/, '')
        term.gsub!("_", "\\_")
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

    def check_hashtag
      tag_values = params[:tag_values].each(&:downcase!)

      valid_tags = TopicCustomField.where(name: TAGS_FIELD_NAME, value: tag_values).map do |tag|
        { value: tag.value, url: "#{Discourse.base_url}/tags/#{tag.value}" }
      end.compact

      render json: { valid: valid_tags }
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

      def set_category_from_params
        slug_or_id = params[:category]
        return true if slug_or_id.nil?

        parent_slug_or_id = params[:parent_category]

        parent_category_id = nil
        if parent_slug_or_id.present?
          parent_category_id = Category.query_parent_category(parent_slug_or_id)
          raise Discourse::NotFound if parent_category_id.blank?
        end

        @filter_on_category = Category.query_category(slug_or_id, parent_category_id)
        raise Discourse::NotFound if !@filter_on_category

        guardian.ensure_can_see!(@filter_on_category)
      end

      def build_topic_list_options
        options = {
          page: params[:page],
          topic_ids: param_to_integer_list(:topic_ids),
          exclude_category_ids: params[:exclude_category_ids],
          category: params[:category],
          order: params[:order],
          ascending: params[:ascending],
          min_posts: params[:min_posts],
          max_posts: params[:max_posts],
          status: params[:status],
          filter: params[:filter],
          state: params[:state],
          search: params[:search],
          q: params[:q]
        }
        options[:no_subcategories] = true if params[:no_subcategories] == 'true'
        options[:slow_platform] = true if slow_platform?

        options
      end
  end

  DiscourseTagging::Engine.routes.draw do
    get '/' => 'tags#index'
    get '/filter/list' => 'tags#index'
    get '/filter/search' => 'tags#search'
    get '/check' => 'tags#check_hashtag'
    constraints(tag_id: /[^\/]+?/, format: /json|rss/) do
      get '/:tag_id.rss' => 'tags#tag_feed'
      get '/:tag_id' => 'tags#show', as: 'list_by_tag'
      get '/c/:category/:tag_id' => 'tags#show'
      get '/c/:parent_category/:category/:tag_id' => 'tags#show'
      get '/:tag_id/notifications' => 'tags#notifications'
      put '/:tag_id/notifications' => 'tags#update_notifications'
      put '/:tag_id' => 'tags#update'
      delete '/:tag_id' => 'tags#destroy'

      Discourse.filters.each do |filter|
        get "/:tag_id/l/#{filter}" => "tags#show_#{filter}"
        get "/c/:category/:tag_id/l/#{filter}" => "tags#show_#{filter}"
        get "/c/:parent_category/:category/:tag_id/l/#{filter}" => "tags#show_#{filter}"
      end
    end
  end

  Discourse::Application.routes.append do
    mount ::DiscourseTagging::Engine, at: "/tags"
  end

  # Add a `tags` reader to the Topic model for easy reading of tags
  add_to_class :topic, :tags do
    result = custom_fields[TAGS_FIELD_NAME]
    [result].flatten unless result.blank?
  end

  # old versions don't get preloading
  TopicList.preloaded_custom_fields << TAGS_FIELD_NAME if TopicList.respond_to? :preloaded_custom_fields

  # Save the tags when the topic is saved
  PostRevisor.track_topic_field(:tags_empty_array) do |tc, val|
    if val.present?
      unless tc.guardian.is_staff?
        old_tags = tc.topic.tags || []
        staff_tags = ::DiscourseTagging.staff_only_tags(old_tags)
        if staff_tags.present?
          tc.topic.errors[:base] << I18n.t("tags.staff_tag_remove_disallowed", tag: staff_tags.join(" "))
          tc.check_result(false)
          next
        end
      end

      tc.record_change(TAGS_FIELD_NAME, tc.topic.custom_fields[TAGS_FIELD_NAME], nil)
      tc.topic.custom_fields.delete(TAGS_FIELD_NAME)
    end
  end

  PostRevisor.track_topic_field(:tags) do |tc, tags|
    if tags.present? && tc.guardian.can_tag_topics?
      tags = ::DiscourseTagging.tags_for_saving(tags, tc.guardian)
      old_tags = tc.topic.tags || []

      new_tags = tags - old_tags
      removed_tags = old_tags - tags

      unless tc.guardian.is_staff?
        staff_tags = ::DiscourseTagging.staff_only_tags(new_tags)
        if staff_tags.present?
          tc.topic.errors[:base] << I18n.t("tags.staff_tag_disallowed", tag: staff_tags.join(" "))
          tc.check_result(false)
          next
        end

        staff_tags = ::DiscourseTagging.staff_only_tags(removed_tags)
        if staff_tags.present?
          tc.topic.errors[:base] << I18n.t("tags.staff_tag_remove_disallowed", tag: staff_tags.join(" "))
          tc.check_result(false)
          next
        end
      end

      tc.record_change(TAGS_FIELD_NAME, tc.topic.custom_fields[TAGS_FIELD_NAME], tags)
      tc.topic.custom_fields.update(TAGS_FIELD_NAME => tags)

      ::DiscourseTagging.auto_notify_for(new_tags, tc.topic) if new_tags.present?
    end
  end

  on(:after_validate_topic) do |topic, topic_creator|
    if !topic_creator.guardian.is_staff? && staff_only = ::DiscourseTagging.staff_only_tags(topic_creator.opts[:tags])
      topic.errors[:base] << I18n.t("tags.staff_tag_disallowed", tag: staff_only.join(" "))
    end
  end

  on(:topic_created) do |topic, params, user|
    guardian = Guardian.new(user)
    tags = ::DiscourseTagging.tags_for_saving(params[:tags], guardian)
    if tags.present?
      topic.custom_fields.update(TAGS_FIELD_NAME => tags)
      topic.save
      ::DiscourseTagging.auto_notify_for(tags, topic)
    end
  end

  add_to_class(:guardian, :can_create_tag?) do
    user && user.has_trust_level?(SiteSetting.min_trust_to_create_tag.to_i)
  end

  add_to_class(:guardian, :can_tag_topics?) do
    user && user.has_trust_level?(SiteSetting.min_trust_level_to_tag_topics.to_i)
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
  add_to_serializer(:site, :can_tag_topics) { scope.can_tag_topics? }
  add_to_serializer(:site, :tags_filter_regexp) { TAGS_FILTER_REGEXP.source }
  add_to_serializer(:topic_list_item, :tags) { object.tags }

  add_to_class(:site_serializer, :include_top_tags?) { SiteSetting.show_filter_by_tag }
  add_to_serializer(:site, :top_tags, false) { ::DiscourseTagging.top_tags }

  add_to_class(:topic_list_serializer, :include_tags?) { SiteSetting.show_filter_by_tag }
  add_to_serializer(:topic_list, :tags, false) { ::DiscourseTagging.top_tags }

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

  if Search.respond_to? :advanced_filter
    Search.advanced_filter(/tags?:([a-zA-Z0-9,\-_]+)/) do |posts, match|

      tags = match.split(",")

      posts.where("topics.id IN (
        SELECT tc.topic_id
        FROM topic_custom_fields tc
        WHERE tc.name = '#{::DiscourseTagging::TAGS_FIELD_NAME}' AND
                        tc.value in (?)
        )", tags)

    end
  end

  if TopicQuery.respond_to?(:results_filter_callbacks)
    remove_muted_for_lists = [:latest, :new]
    remove_muted_tags = Proc.new do |list_type, result, user, options|
      if user.nil? || !remove_muted_for_lists.include?(list_type) ||
          !SiteSetting.tagging_enabled || !SiteSetting.remove_muted_tags_from_latest
        result
      else
        muted_tags = DiscourseTagging.muted_tags(user)
        if muted_tags.empty?
          result
        else
          showing_tag = if options[:filter]
            f = options[:filter].split('/')
            f[0] == 'tags' ? f[1] : nil
          else
            nil
          end

          if muted_tags.include?(showing_tag)
            result # if viewing the topic list for a muted tag, show all the topics
          else
            arr = muted_tags.map{ |z| "'#{z}'" }.join(',')
            result.where("EXISTS (
       SELECT 1
         FROM topic_custom_fields tcf
        WHERE tcf.name = 'tags'
          AND tcf.value NOT IN (#{arr})
          AND tcf.topic_id = topics.id
       ) OR NOT EXISTS (select 1 from topic_custom_fields tcf where tcf.name = 'tags' and tcf.topic_id = topics.id)")
          end
        end
      end
    end

    TopicQuery.results_filter_callbacks << remove_muted_tags
  end

  ::PrettyText::Helpers.class_eval do
    def category_tag_hashtag_lookup(text)
      tag_postfix = '::tag'
      is_tag = text =~ /#{tag_postfix}$/

      if !is_tag && category = Category.query_from_hashtag_slug(text)
        [category.url_with_id, text]
      elsif is_tag && tag = TopicCustomField.find_by(name: TAGS_FIELD_NAME, value: text.gsub!("#{tag_postfix}", ''))
        ["#{Discourse.base_url}/tags/#{tag.value}", text]
      else
        nil
      end
    end

    DiscourseEvent.on(:markdown_context) do |context|
      context.eval('opts["categoryHashtagLookup"] = function(c){return helpers.category_tag_hashtag_lookup(c);}')
    end
  end
end
