export default Ember.Controller.extend({
  tag: null,
  list: null,

  canAdminTag: Ember.computed.alias('currentUser.staff'),

  loadMoreTopics() {
    return this.get('list').loadMore();
  },

  actions: {
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
