import { setting } from 'discourse/lib/computed';
import computed from 'ember-addons/ember-computed-decorators';
import { on } from 'ember-addons/ember-computed-decorators';

export default Ember.Component.extend({
  classNameBindings: [':tag-drop', 'tag::no-category', 'tags:has-drop','categoryStyle','tagClass'],
  categoryStyle: setting('category_style'), // match the category-drop style
  currentCategory: Ember.computed.or('secondCategory', 'firstCategory'),
  showFilterByTag: setting('show_filter_by_tag'),
  showTagDropdown: Ember.computed.and('showFilterByTag', 'tags'),
  tagId: null,
  tagName: 'li',

  @computed("site.top_tags")
  tags() {
    if (this.siteSettings.tags_sort_alphabetically && Discourse.Site.currentProp('top_tags')) {
      return Discourse.Site.currentProp('top_tags').sort();
    } else {
      return Discourse.Site.currentProp('top_tags');
    }
  },

  @computed("expanded")
  iconClass(expanded) {
    return `fa fa-caret-${expanded ? "down" : "right"}`;
  },

  @computed("tagId")
  tagClass(tagId) {
    return tagId ? `tag-${tagId}` : "tag_all";
  },

  @computed("currentCategory", "currentCategory.url")
  allTagsUrl(currentCategory, currentCategoryUrl) {
    return currentCategory ? currentCategoryUrl : "/";
  },

  @computed()
  allTagsLabel() {
    return I18n.t("tagging.selector_all_tags");
  },

  @computed("tag")
  dropdownButtonClass(tag) {
    return `badge-category category-dropdown-button ${Em.isNone(tag) ? "home" : ""}`;
  },

  @computed("tag")
  clickEventName(tag) {
    return `click.tag-drop-${tag || "all"}`;
  },

  actions: {
    expand() {
      if (!this.get('renderTags')) {
        this.set('renderTags', true);
        Ember.run.next(() => this.send('expand'));
        return;
      }

      if (this.get('expanded')) {
        this.close();
        return;
      }

      if (this.get('tags')) {
        this.set('expanded', true);
      }

      const self = this,
            $dropdown = this.$()[0];

      this.$('a[data-drop-close]').on('click.tag-drop', () => this.close());

      Ember.run.next(() => {
        self.$('.cat a').add('html').on(self.get('clickEventName'), e => {
          const $target = $(e.target),
                closest = $target.closest($dropdown);

          if ($(e.currentTarget).hasClass('badge-wrapper')) {
            self.close();
          }

          return ($(e.currentTarget).hasClass('badge-category') || (closest.length && closest[0] === $dropdown)) ? true : self.close();
        });
      });
    }
  },

  removeEvents() {
    $('html').off(this.get('clickEventName'));
    this.$('a[data-drop-close]').off('click.tag-drop');
  },

  close() {
    this.removeEvents();
    this.set('expanded', false);
  },

  @on("willDestroyElement")
  _cleanUp() {
    this.removeEvents();
  }

});
