export default Ember.TextField.extend({
  classNameBindings: [':tag-chooser'],
  attributeBindings: ['tabIndex'],

  _setupTags: function() {
    var tags = this.get('tags') || [];
    this.set('value', tags.join(", "));
  }.on('init'),

  _valueChanged: function() {
    var tags = this.get('value').split(',').map(function(v) {
      return v.trim();
    }).reject(function(v) {
      return v.length === 0;
    }).uniq();

    this.set('tags', tags);
  }.observes('value'),

  _initializeTags: function() {
    var site = this.site;
    this.$().select2({
      tags: true,
      placeholder: I18n.t('tagging.choose_for_topic'),
      maximumSelectionSize: this.siteSettings.max_tags_per_topic,
      initSelection: function (element, callback) {
        var data = [];

        function splitVal(string, separator) {
          var val, i, l;
          if (string === null || string.length < 1) return [];
          val = string.split(separator);
          for (i = 0, l = val.length; i < l; i = i + 1) val[i] = $.trim(val[i]);
          return val;
        }

        $(splitVal(element.val(), ",")).each(function () {
          data.push({
            id: this,
            text: this
          });
        });

        callback(data);
      },
      createSearchChoice: function(term, data) {
        if ($(data).filter(function() {
          return this.text.localeCompare(term) === 0;
        }).length === 0 && site.get('can_create_tag')) {
          return { id: term, text: term };
        }
      },
      multiple: true,
      ajax: {
        quietMillis: 200,
        cache: true,
        url: "/tagging/search",
        dataType: 'json',
        data: function (term) {
          return { q: term };
        },
        results: function (data) {
          return data;
        }
      },
    });
  }.on('didInsertElement'),

  _destroyTags: function() {
    this.$().select2('destroy');
  }.on('willDestroyElement')

});
