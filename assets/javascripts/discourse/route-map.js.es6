export default function() {
  this.resource('tagging', function() {
    this.route('tag', {path: '/tag/:tag_id'});
  });
}
