export default Discourse.Route.extend({
  model(tag) {
    var self = this;
    return Discourse.TopicList.list('tags/' + tag.tag_id).then(function(list) {
      self.set('list', list);
      tag.tag_id = Handlebars.Utils.escapeExpression(tag.tag_id);
      return tag;
    });
  },

  setupController(controller, model) {
    controller.set('tag', model);
    controller.set('list', this.get('list'));
  }
});
