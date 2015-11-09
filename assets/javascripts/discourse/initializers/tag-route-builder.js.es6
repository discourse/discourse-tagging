export default {
  name: 'tag-route-builder',
  initialize(container, app) {
    const site = container.lookup('site:main');
    const TagsShowRoute = container.lookupFactory('route:tags-show');

    app["TagsShowCategoryRoute"] = TagsShowRoute.extend();
    app["TagsShowParentCategoryRoute"] = TagsShowRoute.extend();

    site.get('filters').forEach(function(filter) {
      app["TagsShow" + filter.capitalize() + "Route"] = TagsShowRoute.extend({ filterMode: filter });
      app["TagsShowCategory" + filter.capitalize() + "Route"] = TagsShowRoute.extend({ filterMode: filter });
      app["TagsShowParentCategory" + filter.capitalize() + "Route"] = TagsShowRoute.extend({ filterMode: filter });
    });
  }
};
