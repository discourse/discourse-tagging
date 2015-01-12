export default Ember.Component.extend({
  tagName: 'a',
  classNameBindings: [':discourse-tag'],
  attributeBindings: ['href', 'style'],

  href: function() {
    return "/tagging/tag/" + this.get('tagId');
  }.property('tagId'),

  style: function() {
    var count = parseFloat(this.get('count')),
        minCount = parseFloat(this.get('minCount')),
        maxCount = parseFloat(this.get('maxCount'));

    if (count && maxCount && minCount) {
      var ratio = (count - minCount) / maxCount;
      if (ratio) {
        ratio = ratio + 1.0;
        return "font-size: " + ratio + "em";
      }
    }
  }.property('count', 'scaleTo'),

  render: function(buffer) {
    buffer.push(this.get('tagId'));
  },

  click: function(e) {
    e.preventDefault();
    Discourse.URL.routeTo(this.get('href'));
    return true;
  }
});
