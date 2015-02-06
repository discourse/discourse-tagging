export default Ember.Route.extend({
  model() {
    return Discourse.ajax("/tagging/cloud.json");
  }
});
