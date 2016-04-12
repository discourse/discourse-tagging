import DEditor from 'discourse/components/d-editor';
import ComposerEditor from 'discourse/components/composer-editor';
import { categoryHashtagTriggerRule, SEPARATOR } from 'discourse/lib/category-hashtags';
import { search as searchCategoryTag  } from 'discourse/plugins/discourse-tagging/lib/category-tag-search';
import Category from 'discourse/models/category';
import { fetchUnseenTagHashtags, linkSeenTagHashtags } from 'discourse/plugins/discourse-tagging/lib/link-tag-hashtag';
import { TAG_HASHTAG_POSTFIX } from 'discourse/plugins/discourse-tagging/lib/tag-hashtags';
import { linkSeenCategoryHashtags, fetchUnseenCategoryHashtags } from 'discourse/lib/link-category-hashtags';
import { on } from 'ember-addons/ember-computed-decorators';

export default {
  name: 'apply-tag-autocomplete',

  initialize(container, app) {
    const siteSettings = container.lookup('site-settings:main');

    DEditor.reopen({
      _applyCategoryHashtagAutocomplete() {
        const template = container.lookup('template:category-tag-autocomplete.raw');

        this.$('.d-editor-input').autocomplete({
          template: template,
          key: '#',
          transformComplete(obj) {
            if (obj.model) {
              return Category.slugFor(obj.model, SEPARATOR);
            } else {
              return `${obj.text}${TAG_HASHTAG_POSTFIX}`;
            }
          },
          dataSource(term) {
            return searchCategoryTag(term, siteSettings);
          },
          triggerRule(textarea, opts) {
            return categoryHashtagTriggerRule(textarea, opts);
          }
        });
      }
    });

    ComposerEditor.reopen({
      _renderUnseenTagHashtags($preview, unseen) {
        fetchUnseenTagHashtags(unseen).then(() => {
          linkSeenTagHashtags($preview);
        });
      },

      @on('previewRefreshed')
      paintTagHashtags($preview) {
        if (!siteSettings.tagging_enabled) return;

        const unseenTagHashtags = linkSeenTagHashtags($preview);
        if (unseenTagHashtags.length) {
          Ember.run.debounce(this, this._renderUnseenTagHashtags, $preview, unseenTagHashtags, 500);
        }
      }
    });
  }
};
