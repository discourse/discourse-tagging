export default Ember.Controller.extend({
  tag: null,
  list: null,

  canRenameTag: Ember.computed.alias('currentUser.staff'),

  loadMoreTopics() {
    return this.get('list').loadMore();
  },

  actions: {
    changeTagNotification(id) {
      const tagNotification = this.get('tagNotification');
      tagNotification.update({ notification_level: id });
    }
  }
});
