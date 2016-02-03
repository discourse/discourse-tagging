import { acceptance } from "helpers/qunit-helpers";
import { search } from 'discourse/plugins/discourse-tagging/lib/category-tag-search';
acceptance("Tag Autocomplete", {
  loggedIn: true,
  setup() {
    const response = (object) => {
      return [
        200,
        {"Content-Type": "application/json"},
        object
      ];
    }

    server.get('/tags/filter/search', () => {
      return response({ results: [{ text: 'monkey', count: 1 }] });
    });

    server.get('/category_hashtags/check', () => {
      return response({ valid: [] });
    })

    server.get('/tags/check', () => {
      return response({ valid: [{ value: 'monkey', url: '/tags/monkey' }] })
    });
  }
});

test("tag is cooked properly", () => {
  visit("/");
  click('#create-topic');

  fillIn('.d-editor-input', "this is a tag hashtag #monkey::tag");
  andThen(() => {
    // TODO: Test that the autocomplete shows
    equal(find('.d-editor-preview:visible').html().trim(), "<p>this is a tag hashtag <a href=\"/tags/monkey\" class=\"hashtag\">#<span>monkey</span></a></p>");
  });
});
