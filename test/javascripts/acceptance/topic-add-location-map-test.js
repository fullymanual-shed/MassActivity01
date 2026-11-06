import { click, fillIn, visit, waitFor } from "@ember/test-helpers";
import { test } from "qunit";
import { cloneJSON } from "discourse/lib/object";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";
import locationFixtures from "discourse/plugins/discourse-locations/test/javascripts/fixtures/location-fixtures";
import siteFixtures from "discourse/plugins/discourse-locations/test/javascripts/fixtures/site-fixtures";
import topicFixtures from "discourse/plugins/discourse-locations/test/javascripts/fixtures/topic-fixtures";

acceptance("MassActivity01 - Location picker", function (needs) {
  needs.user({
    username: "demetria_gutmann",
    id: 134,
  });
  needs.settings({
    location_enabled: true,
    location_geocoding: "optional",
    location_input_fields_enabled: true,
    location_input_fields: "street|postalcode|city|countrycode|coordinates",
  });
  needs.site(cloneJSON(siteFixtures["site.json"]));
  needs.pretender((server, helper) => {
    const topicResponse = cloneJSON(topicFixtures["/t/51/1.json"]);
    server.get("/t/51/1.json", () => helper.response(topicResponse));
    const locationResponse = cloneJSON(locationFixtures["location.json"]);
    server.get("/locations/search", () => helper.response(locationResponse));
  });

  test("opens the address search and map from Add a Location", async function (assert) {
    await visit("/t/online-learning/51/1");
    await click("a.fancy-title");
    await click("button.add-location-btn");

    assert.dom(".add-location-modal").isVisible();
    assert.dom(".mass-activity-location-search input").exists();
    assert.dom(".location-form").doesNotExist();
    assert.dom(".mass-activity-location-map .leaflet-container").exists();
    assert.true(
      document
        .querySelector(".mass-activity-location-map")
        .getBoundingClientRect().height > 0,
      "the Leaflet map container has a visible height"
    );
    assert.dom("button.add-location-btn").exists();

    await fillIn(".mass-activity-location-search input", "liver building");
    await waitFor(".mass-activity-location-results button");
    assert.strictEqual(
      getComputedStyle(
        document.querySelector(".mass-activity-location-results")
      ).position,
      "absolute",
      "address suggestions appear in an overlay"
    );
    await click(".mass-activity-location-results button:first-child");

    assert.dom(".mass-activity-location-map-coordinates").exists();
    assert.dom(".mass-activity-location-map .leaflet-interactive").exists();

    await click("#save-location");
    assert.dom(".add-location-modal").doesNotExist();
    assert.dom("button.add-location-btn").exists();
  });
});
