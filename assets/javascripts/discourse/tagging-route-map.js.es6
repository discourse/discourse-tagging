export default function() {
  this.resource('tags', function() {
    this.route('show', {path: '/:tag_id'});
    this.route('showCategory', {path: '/c/:category/:tag_id'});
    this.route('showParentCategory', {path: '/c/:parent_category/:category/:tag_id'});

    Discourse.Site.currentProp('filters').forEach(filter => {
      this.route('show' + filter.capitalize(), {path: '/:tag_id/l/' + filter});
      this.route('showCategory' + filter.capitalize(), {path: '/c/:category/:tag_id/l/' + filter});
      this.route('showParentCategory' + filter.capitalize(), {path: '/c/:parent_category/:category/:tag_id/l/' + filter});
    });
  });
}
