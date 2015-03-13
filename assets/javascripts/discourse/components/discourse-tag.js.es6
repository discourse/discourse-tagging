export default Ember.Component.extend({
  tagName: 'a',
  classNameBindings: [':discourse-tag'],
  attributeBindings: ['href'],

  href: function() {
    return "/tags/" + this.get('tagId');
  }.property('tagId'),

  render(buffer) {
    buffer.push(Handlebars.Utils.escapeExpression(this.get('tagId')));
  },

  click(e) {
    e.preventDefault();
    Discourse.URL.routeTo(this.get('href'));
    return true;
  }
});
