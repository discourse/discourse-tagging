# name: discourse-tagging
# about: Support for tagging topics in Discourse
# version: 0.1
# authors: Robin Ward

after_initialize do
  TAGS_FIELD_NAME = "tags"

  module ::DiscourseTagging
    class Engine < ::Rails::Engine
      engine_name "discourse_tagging"
      isolate_namespace DiscourseTagging
    end
  end

  require_dependency 'application_controller'
  require_dependency 'topic_list_responder'
  class DiscourseTagging::TaggingController < ::ApplicationController
    include ::TopicListResponder

    def cloud
      cloud = TopicCustomField.where(name: TAGS_FIELD_NAME).group(:value).count

      result = []
      max_count = 0
      min_count = nil
      cloud.each do |t, c|
        result << { id: t, count: c }
        max_count = c if c > max_count
        min_count = c if min_count.nil? || c < min_count
      end

      render json: { cloud: result, max_count: max_count, min_count: min_count }
    end

    def show
      topics_tagged = TopicCustomField.where(name: TAGS_FIELD_NAME, value: params[:tag_id]).pluck(:topic_id)

      query = TopicQuery.new(current_user)
      latest_results = query.latest_results.where(id: topics_tagged)
      list = query.create_list(:by_tag, {}, latest_results)

      respond_with_list(list)
    end

    def search
      # Tag searcher
      tags = TopicCustomField.where(name: TAGS_FIELD_NAME)
                             .group(:value)
                             .limit(5)
                             .order('COUNT(topic_custom_fields.value) DESC')

      term = params[:q]
      if term.present?
        term.gsub!(/[^a-z0-9]*/, '')
        tags = tags.where('value like ?', "%#{term}%")
      end

      tags = tags.count(:value).map {|t, _| { id: t, text: t } }

      render json: { results: tags }
    end
  end

  DiscourseTagging::Engine.routes.draw do
    get '/' => 'tagging#cloud'
    get '/cloud' => 'tagging#cloud'
    get '/search' => 'tagging#search'
    get '/tag/:tag_id' => 'tagging#show'
  end

  Discourse::Application.routes.append do
    mount ::DiscourseTagging::Engine, at: "/tagging"
  end

  # Save the tags when the topic is saved
  DiscourseEvent.on(:topic_saved) do |topic, params, current_user|
    if params['tags_empty_array']
      topic.custom_fields.delete(TAGS_FIELD_NAME)
      topic.save
    end

    if params['tags'].present?
      tags = params['tags']
      tags.map! {|t| t.downcase.strip[0...SiteSetting.max_tag_length].gsub(/[<\\\/\>]/, '') }
      tags.delete_if {|t| t.blank? }
      tags.uniq!

      # If the user can't create tags, remove any tags that don't already exist
      unless Guardian.new(current_user).can_create_tag?
        tag_count = TopicCustomField.where(name: TAGS_FIELD_NAME, value: tags).group(:value).count
        tags.delete_if {|t| !tag_count.has_key?(t) }
      end

      topic.custom_fields.update(TAGS_FIELD_NAME => tags[0...SiteSetting.max_tags_per_topic])
      topic.save
    end
  end

  # Allow us to pass tags as parameters with our posts/topics
  DiscourseEvent.on(:permit_post_params) do |result, params|
    tags = params.permit(:tags => [])
    result.merge!(tags) if tags.present?
  end

  add_to_serializer(:topic_view, :tags) do
    result = object.topic.custom_fields[TAGS_FIELD_NAME]
    return [result].flatten if result
  end

  add_to_serializer(:site, :can_create_tag) { scope.can_create_tag? }

  module AddCanCreateTagToGuardian
    def can_create_tag?
      user && user.has_trust_level?(SiteSetting.min_trust_to_create_tag)
    end
  end
  Guardian.send(:include, AddCanCreateTagToGuardian)

end

register_asset 'stylesheets/tagging.scss'
