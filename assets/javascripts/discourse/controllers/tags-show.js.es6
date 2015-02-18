export default Ember.Controller.extend({
  tag: null,
  list: null,

  loadMoreTopics() {
    return this.get('list').loadMore();
  }
});
