import BulkTopicSelection from 'discourse/mixins/bulk-topic-selection';

export default Ember.Controller.extend(BulkTopicSelection, {
  tag: null,
  list: null,

  canAdminTag: Ember.computed.alias('currentUser.staff'),

  loadMoreTopics() {
    return this.get('list').loadMore();
  },

  actions: {
    refresh() {
      const self = this;
      return Discourse.TopicList.list('tags/' + this.get('tag.id')).then(function(list) {
        self.set('list', list);
        self.resetSelected();
      });
    },

    deleteTag() {
      const self = this;
      bootbox.confirm(I18n.t('tagging.delete_confirm'), function(result) {
        if (!result) { return; }

        self.get('tag').destroyRecord().then(function() {
          self.transitionToRoute('tags.index');
        }).catch(function() {
          bootbox.alert(I18n.t('generic_error'));
        });
      });
    },

    changeTagNotification(id) {
      const tagNotification = this.get('tagNotification');
      tagNotification.update({ notification_level: id });
    }
  }
});
