export default Discourse.Route.extend({
  model() {
    return Discourse.ajax("/tagging/cloud.json");
  }
});
