import showModal from 'discourse/lib/show-modal';

export default Discourse.Route.extend({

  model(tag) {
    tag = this.store.createRecord('tag', { id: Handlebars.Utils.escapeExpression(tag.tag_id) });

    if (this.get('currentUser')) {
      // If logged in, we should get the tag's user settings
      const self = this;
      return this.store.find('tagNotification', tag.get('id')).then(function(tn) {
        self.set('tagNotification', tn);
        return tag;
      });
    }

    return tag;
  },

  afterModel(tag) {
    const self = this;
    return Discourse.TopicList.list('tags/' + tag.get('id')).then(function(list) {
      self.controllerFor('tags.show').set('list', list);
    });
  },

  setupController(controller, model) {
    controller.setProperties({
      tag: model,
      tagNotification: this.get('tagNotification')
    });
  },

  actions: {
    renameTag: function(tag) {
      showModal('rename-tag', tag);
    }
  }
});
