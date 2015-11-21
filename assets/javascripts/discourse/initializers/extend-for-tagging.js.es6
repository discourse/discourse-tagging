import ComposerController from 'discourse/controllers/composer';
import HistoryController from 'discourse/controllers/history';
import TopicController from 'discourse/controllers/topic';
import { needsSecondRowIf } from 'discourse/components/header-extra-info';
import { addBulkButton } from 'discourse/controllers/topic-bulk-actions';
import TopicBulkActionsController from 'discourse/controllers/topic-bulk-actions';
import registerUnbound from 'discourse/helpers/register-unbound';
import renderTag from 'discourse/plugins/discourse-tagging/lib/render-tag';
import Topic from 'discourse/models/topic';
import Composer from 'discourse/models/composer';

// Work around a quirk of custom fields -- an array of one element
// is returned as just that element. We should fix this properly
// in custom fields and remove this.
function customTagArray(fieldName) {
  return function() {
    var val = this.get(fieldName);
    if (!val) { return val; }
    if (!Array.isArray(val)) { val = [val]; }
    return val;
  }.property(fieldName);
}

export default {
  name: 'extend-for-tagging',
  initialize() {
    Composer.serializeOnCreate('tags');
    Composer.serializeToTopic('tags', 'topic.tags');

    TopicController.reopen({
      canEditTags: function() {
        return !this.get('model.isPrivateMessage') && this.site.get('can_tag_topics');
      }.property('model.isPrivateMessage')
    });

    HistoryController.reopen({
      previousTagChanges: customTagArray('model.tags_changes.previous'),
      currentTagChanges: customTagArray('model.tags_changes.current')
    });

    ComposerController.reopen({
      canEditTags: function() {
        return !this.site.mobileView &&
                this.site.get('can_tag_topics') &&
                this.get('model.canEditTitle') &&
                !this.get('model.creatingPrivateMessage');
      }.property('model.canEditTitle', 'model.creatingPrivateMessage')
    });

    addBulkButton('showTagTopics', 'change_tags');
    TopicBulkActionsController.reopen({
      tags: null,
      emptyTags: Ember.computed.empty('tags'),

      actions: {
        showTagTopics() {
          this.set('tags', '');
          this.send('changeBulkTemplate', 'bulk-tag');
        },

        changeTags() {
          this.performAndRefresh({type: 'change_tags', tags: this.get('tags')});
        }
      }
    });


    // Show a second row in the header if there are any tags on the topic
    needsSecondRowIf('topic.tags.length', tagsLength => parseInt(tagsLength) > 0);

    // we need something unbound for raw templates
    registerUnbound('discourse-tag', function(name, params) {
      return new Handlebars.SafeString(renderTag(name, params));
    });

    Topic.reopen({
      visibleListTags: function(){
        var tags = this.get('tags');
        if (!tags || !Discourse.SiteSettings.suppress_overlapping_tags_in_list) {
          return tags;
        }

        var title = this.get('title');
        var newTags = [];

        tags.forEach(function(tag){
          if (title.toLowerCase().indexOf(tag) === -1 || Discourse.SiteSettings.staff_tags.indexOf(tag) !== -1) {
            newTags.push(tag);
          }
        });

        return newTags;
      }.property('tags')
    });
  }
};
