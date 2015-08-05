import showModal from "discourse/lib/show-modal";

export default Discourse.Route.extend({

  model(tag) {
    tag = this.store.createRecord("tag", { id: Handlebars.Utils.escapeExpression(tag.tag_id) });

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
    return Discourse.TopicList.list("tags/" + tag.get("id")).then(list => {
      this.controllerFor("tags.show").set("list", list);
    });
  },

  setupController(controller, model) {
    controller.setProperties({
      tag: model,
      tagNotification: this.get("tagNotification")
    });
  },

  actions: {
    renameTag(tag) {
      showModal("rename-tag", tag);
    },

    didTransition() {
      this.controllerFor("tags.show")._showFooter();
      return true;
    }
  }
});
