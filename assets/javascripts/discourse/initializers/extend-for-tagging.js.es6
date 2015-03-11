import ComposerController from 'discourse/controllers/composer';
import HistoryController from 'discourse/controllers/history';
import TopicController from 'discourse/controllers/topic';
import { needsSecondRowIf } from 'discourse/components/header-extra-info';
import { addBulkButton } from 'discourse/controllers/topic-bulk-actions';
import TopicBulkActionsController from 'discourse/controllers/topic-bulk-actions';

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
    Discourse.Composer.serializeOnCreate('tags');
    Discourse.Composer.serializeToTopic('tags', 'topic.tags');

    TopicController.reopen({
      canEditTags: Ember.computed.not('isPrivateMessage')
    });

    HistoryController.reopen({
      previousTagChanges: customTagArray('tags_changes.previous'),
      currentTagChanges: customTagArray('tags_changes.current')
    });

    ComposerController.reopen({
      canEditTags: function() {
        return !this.site.mobileView &&
                this.get('model.canEditTitle') &&
                !this.get('model.creatingPrivateMessage');
      }.property('model.canEditTitle', 'model.creatingPrivateMessage')
    });

    addBulkButton('showTagTopics', 'change_tags');
    TopicBulkActionsController.reopen({
      actions: {
        showTagTopics() {
          this.set('tags', '');
          this.send('changeBulkTemplate', 'bulk-tag');
        },

        changeTags() {
          const self = this;
          this.performAndRefresh({type: 'change_tags', tags: this.get('tags')});
        }
      }
    });


    // Show a second row in the header if there are any tags on the topic
    needsSecondRowIf('topic.tags.length', tagsLength => parseInt(tagsLength) > 0);
  }
};
