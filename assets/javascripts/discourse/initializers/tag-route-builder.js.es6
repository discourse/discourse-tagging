export default {
  name: 'tag-route-builder',
  initialize(container, app) {
    const site = container.lookup('site:main');
    const TagsShowRoute = container.lookupFactory('route:tags-show'); // use . or - ???
    const TagsShowController = container.lookupFactory('controller:tags-show');

    site.get('filters').forEach(function(filter) {
      app["TagsShow" + filter.capitalize() + "Route"] = TagsShowRoute;
    });
  }
}
