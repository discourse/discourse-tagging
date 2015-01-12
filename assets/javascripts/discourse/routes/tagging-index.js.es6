export default Ember.Route.extend({
  model: function() {
    return Discourse.ajax("/tagging/cloud.json");
  }
});
