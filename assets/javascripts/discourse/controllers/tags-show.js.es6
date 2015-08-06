import BulkTopicSelection from "discourse/mixins/bulk-topic-selection";
import NavItem from 'discourse/models/nav-item';
import { extraNavItemProperties, customNavItemHref } from 'discourse/models/nav-item';

if (extraNavItemProperties) {
  extraNavItemProperties(function(text, opts) {
    if (opts && opts.tagId) {
      return {tagId: opts.tagId};
    } else {
      return {};
    }
  });
}

if (customNavItemHref) {
  customNavItemHref(function(navItem) {
    if (navItem.get('tagId')) {
      var path = "/tags/",
          name = navItem.get('name'),
          category = navItem.get("category");

      if(category){
        path += "c/";
        path += Discourse.Category.slugFor(category);
        if (navItem.get('noSubcategories')) { path += '/none'; }
        path += "/";
      }

      path += navItem.get('tagId') + "/l/";
      return path + name.replace(' ', '-');
    } else {
      return null;
    }
  });
}

export default Ember.Controller.extend(BulkTopicSelection, {
  needs: ["application"],

  tag: null,
  list: null,
  canAdminTag: Ember.computed.alias("currentUser.staff"),
  filterMode: null,

  navItems: function() {
    var x = NavItem.buildList(this.get('category'), {tagId: this.get('tag.id'), filterMode: this.get('filterMode')});
    return x;
  }.property('category', 'tag.id', 'filterMode'),

  showTagFilter: function() {
    return Discourse.SiteSettings.show_filter_by_tag;
  }.property('category'),

  categories: function() {
    return Discourse.Category.list();
  }.property(),

  showAdminControls: function() {
    return this.get('canAdminTag') && !this.get('category');
  }.property('canAdminTag', 'category'),

  loadMoreTopics() {
    return this.get("list").loadMore();
  },

  _showFooter: function() {
    this.set("controllers.application.showFooter", !this.get("list.canLoadMore"));
  }.observes("list.canLoadMore"),

  actions: {
    refresh() {
      const self = this;
      // TODO: this probably doesn't work anymore
      return this.store.findFiltered('topicList', {filter: 'tags/' + this.get('tag.id')}).then(function(list) {
        self.set("list", list);
        self.resetSelected();
      });
    },

    deleteTag() {
      const self = this;
      bootbox.confirm(I18n.t("tagging.delete_confirm"), function(result) {
        if (!result) { return; }

        self.get("tag").destroyRecord().then(function() {
          self.transitionToRoute("tags.index");
        }).catch(function() {
          bootbox.alert(I18n.t("generic_error"));
        });
      });
    },

    changeTagNotification(id) {
      const tagNotification = this.get("tagNotification");
      tagNotification.update({ notification_level: id });
    }
  }
});
