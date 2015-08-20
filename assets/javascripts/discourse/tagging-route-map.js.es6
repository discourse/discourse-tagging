export default function() {
  this.resource('tags', function() {
    this.route('show', {path: ':tag_id'});
    this.route('show', {path: '/c/:category/:tag_id'});
    this.route('show', {path: '/c/:parent_category/:category/:tag_id'});

    var self = this;

    Discourse.Site.currentProp('filters').forEach(function(filter) {
      self.route('show' + filter.capitalize(), {path: ':tag_id/l/' + filter});
      self.route('show' + filter.capitalize(), {path: '/c/:category/:tag_id/l/' + filter});
      self.route('show' + filter.capitalize(), {path: '/c/:parent_category/:category/:tag_id/l/' + filter});
    });
  });
}
