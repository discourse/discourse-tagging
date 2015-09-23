import OpenComposer from "discourse/mixins/open-composer";
import showModal from "discourse/lib/show-modal";

export default Discourse.Route.extend(OpenComposer, {

  renderTemplate: function() {
    this.render('tags.show');
  },

  beforeModel(transition) {
    this.set('intentUrl', transition.intent.url.substr(1));
    var split = transition.intent.url.split("/").reverse();
    if (split[1] === "l") {
      this.set('navMode', split[0]);
    } else {
      this.set('navMode', 'latest');
    }
  },

  model(params) {
    var tag = this.store.createRecord("tag", { id: Handlebars.Utils.escapeExpression(params.tag_id) }),
        f = '';

    if (params.category) {
      f = 'c/';
      if (params.parent_category) { f += params.parent_category + '/'; }
      f += params.category + '/l/';
    }
    f += this.get('navMode');
    this.set('filterMode', f);

    this.set('categorySlug', params.category);
    this.set('parentCategorySlug', params.parent_category);

    if (this.get("currentUser")) {
      // If logged in, we should get the tag"s user settings
      return this.store.find("tagNotification", tag.get("id")).then(tn => {
        this.set("tagNotification", tn);
        return tag;
      });
    }

    return tag;
  },

  afterModel(tag) {
    const self = this,
          controller = this.controllerFor('tags.show');

    controller.set('loading', true);

    var url = 'tags/';

    if (this.get('categorySlug')) {
      var category = Discourse.Category.findBySlug(this.get('categorySlug'), this.get('parentCategorySlug'));
      this.set('category', category);
      url += category.get('url') + "/";
    } else {
      this.set('category', null);
    }

    url += tag.get('id');

    return this.store.findFiltered('topicList', {filter: this.get('intentUrl')}).then(function(list) {
      controller.set('list', list);
      controller.set('canCreateTopic', list.get('can_create_topic'));
      if (list.topic_list.tags) {
        Discourse.Site.currentProp('top_tags', list.topic_list.tags);
      }
      controller.set('loading', false);
    });
  },

  setupController(controller, model) {
    this.controllerFor('tags.show').setProperties({
      model,
      tag: model,
      category: this.get('category'),
      filterMode: this.get('filterMode'),
      navMode: this.get('navMode'),
      tagNotification: this.get('tagNotification')
    });
  },

  filterTargetRoutes: ["discovery.parentCategory", "discovery.category", "discovery.latest"],

  actions: {
    renameTag(tag) {
      showModal("rename-tag", tag);
    },

    createTopic() {
      this.openComposer(this.controllerFor("discovery/topics"));
    },

    didTransition() {
      this.controllerFor("tags.show")._showFooter();
      return true;
    },

    willTransition(transition) {
      if (this.filterTargetRoutes.indexOf(transition.targetName) !== -1 && !transition.queryParams.allTags) {
        if (transition.targetName == "discovery.latest") {
          this.transitionTo("/tags/" + this.currentModel.get("id"));
        } else {
          this.transitionTo("/tags" + transition.intent.url + "/" + this.currentModel.get("id"));
        }
      }
      return true;
    }
  }
});
