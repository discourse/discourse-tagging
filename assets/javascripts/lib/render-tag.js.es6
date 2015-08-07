var renderTag = function(tag, params) {
  params = params || {};
  tag = Handlebars.Utils.escapeExpression(tag);
  var classes = ['tag-' + tag, 'discourse-tag'];
  var tagName = params.tagName || "a";
  var href = tagName === "a" ? " href='" + Discourse.getURL("/tags/" + tag) + "' " : "";

  if (Discourse.SiteSettings.tag_style || params.style) {
    classes.push(params.style || Discourse.SiteSettings.tag_style);
  }


  var val = "<" + tagName + href + " class='" + classes.join(" ") + "'>" + tag + "</" + tagName + ">";

  if (params.count) {
    val += " <span class='discourse-tag-count'>x" + params.count + "</span>";
  }

  return val;
};

export default renderTag;
