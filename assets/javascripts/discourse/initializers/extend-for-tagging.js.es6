import ComposerController from 'discourse/controllers/composer';
import TopicController from 'discourse/controllers/topic';

export default {
  name: 'extend-for-tagging',
  initialize: function() {
    Discourse.Composer.serializeOnCreate('tags');
    Discourse.Composer.serializeToTopic('tags', 'topic.tags');

    TopicController.reopen({
      canEditTags: Ember.computed.not('isPrivateMessage')
    });

    ComposerController.reopen({
      canEditTags: function() {
        return !this.site.mobileView &&
                this.get('model.canEditTitle') &&
                !this.get('model.creatingPrivateMessage');
      }.property('model.canEditTitle', 'model.creatingPrivateMessage')
    });
  }
};
