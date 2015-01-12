export default Ember.Route.extend({
  model: function(tag) {
    var self = this;
    tag.tag_id = tag.tag_id.replace(/[^a-z0-9 ]/, '');
    return Discourse.TopicList.list('tagging/tag/' + tag.tag_id).then(function(list) {
      self.set('list', list);
      return tag;
    });
  },

  setupController: function(controller, model) {
    controller.set('tag', model);
    controller.set('list', this.get('list'));
  }
});
