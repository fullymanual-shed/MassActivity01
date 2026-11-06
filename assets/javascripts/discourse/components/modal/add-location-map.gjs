/* global L */
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { Input } from "@ember/component";
import { registerDestructor } from "@ember/destroyable";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import DButton from "discourse/ui-kit/d-button";
import DModal from "discourse/ui-kit/d-modal";
import { i18n } from "discourse-i18n";
import { geoLocationSearch } from "discourse/plugins/discourse-locations/discourse/lib/location-utilities";
import { generateMap } from "discourse/plugins/discourse-locations/discourse/lib/map-utilities";

export default class AddLocationMapModal extends Component {
  @service siteSettings;

  @tracked flash = this.args.model?.flash;
  @tracked name = null;
  @tracked searchTerm = "";
  @tracked searchResults = [];
  @tracked selectedLocation = null;
  @tracked selectedCoordinates = null;
  @tracked isSearching = false;
  @tracked isReverseGeocoding = false;

  map = null;
  mapElement = null;
  marker = null;
  searchRequestId = 0;
  title = i18n("composer.location.title");

  constructor() {
    super(...arguments);

    const location = this.args.model.location;
    if (location) {
      this.name = location.name;
      this.selectedLocation = {
        ...location,
        ...(location.geo_location || {}),
        address: location.geo_location?.address || location.raw,
      };
      this.searchTerm = this.selectedLocation.address || "";
      this.setSelectedCoordinates(location.geo_location);
    }

    registerDestructor(this, () => {
      this.map?.off("click", this.selectPoint);
      this.map?.remove();
      this.mapElement?.remove();
    });
  }

  get submitDisabled() {
    return (
      this.isSearching ||
      this.isReverseGeocoding ||
      (this.siteSettings.location_geocoding === "required" &&
        !this.hasCoordinates(this.selectedLocation))
    );
  }

  hasCoordinates(location) {
    return (
      location?.lat !== undefined &&
      location?.lat !== null &&
      location.lat !== "" &&
      location?.lon !== undefined &&
      location?.lon !== null &&
      location.lon !== "" &&
      Number.isFinite(Number(location.lat)) &&
      Number.isFinite(Number(location.lon))
    );
  }

  setSelectedCoordinates(location) {
    if (!this.hasCoordinates(location)) {
      this.selectedCoordinates = null;
      this.marker?.remove();
      this.marker = null;
      return;
    }

    this.selectedCoordinates = {
      lat: Number(location.lat),
      lon: Number(location.lon),
    };
    this.updateMarker(this.selectedCoordinates);
  }

  @action
  setupMap(element) {
    const center = this.selectedCoordinates
      ? [this.selectedCoordinates.lat, this.selectedCoordinates.lon]
      : [
          Number(this.siteSettings.location_map_center_lat),
          Number(this.siteSettings.location_map_center_lon),
        ];
    const zoom = this.selectedCoordinates
      ? Number(this.siteSettings.location_map_marker_zoom)
      : Number(this.siteSettings.location_map_zoom);

    const mapObjects = generateMap(this.siteSettings, { center, zoom });
    this.map = mapObjects.map;
    this.mapElement = mapObjects.element;
    this.mapElement.style.width = "100%";
    this.mapElement.style.height = "100%";
    element.appendChild(this.mapElement);

    if (this.selectedCoordinates) {
      this.updateMarker(this.selectedCoordinates);
    }

    this.map.on("click", this.selectPoint);
    requestAnimationFrame(() => {
      requestAnimationFrame(() => this.map?.invalidateSize());
    });
  }

  updateMarker(coordinates) {
    if (!this.map) {
      return;
    }

    if (this.marker) {
      this.marker.setLatLng([coordinates.lat, coordinates.lon]);
    } else {
      this.marker = L.circleMarker([coordinates.lat, coordinates.lon], {
        color: "#2f7fc1",
        fillColor: "#2f7fc1",
        fillOpacity: 0.9,
        radius: 8,
      }).addTo(this.map);
    }

    this.map.setView(
      [coordinates.lat, coordinates.lon],
      Math.max(
        this.map.getZoom(),
        Number(this.siteSettings.location_map_marker_zoom)
      )
    );
  }

  @action
  searchAddresses(event) {
    this.searchTerm = event.target.value;
    this.searchResults = [];
    this.flash = null;
    this.isReverseGeocoding = false;
    const requestId = ++this.searchRequestId;
    const term = this.searchTerm.trim();

    if (this.selectedLocation?.address !== term) {
      this.selectedLocation = null;
      this.selectedCoordinates = null;
      this.marker?.remove();
      this.marker = null;
    }

    if (term.length < 3) {
      this.isSearching = false;
      return;
    }

    this.isSearching = true;
    geoLocationSearch(
      { query: term },
      this.siteSettings.location_geocoding_debounce
    )
      .then((result) => {
        if (requestId !== this.searchRequestId) {
          return;
        }

        if (result?.error) {
          throw new Error(result.error);
        }

        this.searchResults = (result.locations || []).map((location) => ({
          ...location,
          id: location.address || JSON.stringify(location),
        }));
      })
      .catch((error) => {
        if (requestId === this.searchRequestId) {
          this.flash =
            error?.message || error || i18n("mass_activity.location_map.error");
        }
      })
      .finally(() => {
        if (requestId === this.searchRequestId) {
          this.isSearching = false;
        }
      });
  }

  @action
  selectAddress(location) {
    this.searchRequestId++;
    this.isReverseGeocoding = false;
    this.searchTerm = location.address || "";
    this.searchResults = [];
    this.flash = null;
    this.isSearching = false;
    this.selectedLocation = location;
    this.selectedCoordinates = null;
    this.setSelectedCoordinates(location);
  }

  @action
  async selectPoint(event) {
    const { lat, lng: lon } = event.latlng;
    const coordinates = { lat, lon };
    const query = `${lat}, ${lon}`;
    const requestId = ++this.searchRequestId;

    this.searchTerm = query;
    this.searchResults = [];
    this.isSearching = false;
    this.selectedLocation = null;
    this.selectedCoordinates = coordinates;
    this.updateMarker(coordinates);
    this.flash = null;

    if (this.siteSettings.location_geocoding === "none") {
      this.selectedLocation = { ...coordinates, address: query };
      return;
    }

    this.isReverseGeocoding = true;
    try {
      const result = await ajax({
        url: "/locations/search",
        data: { request: { query } },
      });

      if (requestId !== this.searchRequestId) {
        return;
      }

      if (result?.error || result?.errors?.length) {
        throw new Error(
          result.message ||
            result.errors?.[0] ||
            i18n("mass_activity.location_map.error")
        );
      }

      const match = result.locations?.[0];
      if (!match && this.siteSettings.location_geocoding === "required") {
        this.flash = i18n("mass_activity.location_map.no_address");
        return;
      }

      this.selectedLocation = {
        ...(match || {}),
        ...coordinates,
        address: match?.address || query,
      };
      this.searchTerm = this.selectedLocation.address;
    } catch (error) {
      if (requestId !== this.searchRequestId) {
        return;
      }

      this.flash = error?.message || i18n("mass_activity.location_map.error");
      if (this.siteSettings.location_geocoding !== "required") {
        this.selectedLocation = { ...coordinates, address: query };
      }
    } finally {
      if (requestId === this.searchRequestId) {
        this.isReverseGeocoding = false;
      }
    }
  }

  @action
  clear() {
    this.args.model.update(null);
    this.args.closeModal();
  }

  @action
  submit() {
    if (this.submitDisabled) {
      return;
    }

    const locationData = this.selectedLocation || {
      address: this.searchTerm.trim(),
    };
    let location = { raw: locationData.address || this.searchTerm.trim() };
    const inputFields = this.siteSettings.location_input_fields.split("|");

    inputFields
      .filter((field) => field !== "coordinates")
      .forEach((field) => {
        if (locationData[field]) {
          location[field] = locationData[field];
        }
      });

    if (
      this.siteSettings.location_geocoding !== "none" ||
      inputFields.includes("coordinates") ||
      this.selectedCoordinates
    ) {
      if (this.hasCoordinates(locationData)) {
        location.geo_location = {
          lat: Number(locationData.lat),
          lon: Number(locationData.lon),
        };
      }
    }

    if (this.name) {
      location.name = this.name;
    }

    if (Object.keys(location).every((key) => !location[key])) {
      location = null;
    }

    this.args.model.update(location);
    this.args.closeModal();
  }

  <template>
    <DModal
      class="add-location add-location-modal"
      @closeModal={{@closeModal}}
      @flash={{this.flash}}
      @title={{this.title}}
    >
      <div class="mass-activity-location-map-section">
        <label class="control-label" for="mass-activity-location-search">
          {{i18n "location.query.title"}}
        </label>
        <div
          class="mass-activity-location-search"
          style="position: relative; margin-bottom: 1em;"
        >
          <Input
            class="input-xxlarge input-location"
            id="mass-activity-location-search"
            style="box-sizing: border-box; width: 100%; max-width: none;"
            @type="search"
            @value={{this.searchTerm}}
            {{on "input" this.searchAddresses}}
          />
          {{#if this.isSearching}}
            <span class="mass-activity-location-map-loading" role="status">
              {{i18n "mass_activity.location_map.loading"}}
            </span>
          {{/if}}
          {{#if this.searchResults.length}}
            <ul
              class="mass-activity-location-results"
              style="position: absolute; z-index: 1000; top: calc(100% + 2px); left: 0; box-sizing: border-box; width: 100%; max-height: 240px; overflow-y: auto; margin: 0; padding: 0; list-style: none; background: var(--secondary); border: 1px solid var(--primary-low); box-shadow: 0 2px 6px rgb(0 0 0 / 20%);"
            >
              {{#each this.searchResults as |location|}}
                <li>
                  <button
                    class="btn btn-default mass-activity-location-result"
                    style="display: block; width: 100%; padding: 0.6em 0.75em; text-align: left;"
                    type="button"
                    {{on "click" (fn this.selectAddress location)}}
                  >{{location.address}}</button>
                </li>
              {{/each}}
            </ul>
          {{/if}}
        </div>
        <p>{{i18n "mass_activity.location_map.instructions"}}</p>
        <div
          class="mass-activity-location-map"
          style="width: 100%; height: min(45vh, 400px); min-height: 260px; position: relative;"
          {{didInsert this.setupMap}}
        ></div>
        {{#if this.selectedCoordinates}}
          <p class="mass-activity-location-map-coordinates">
            {{i18n
              "mass_activity.location_map.selected"
              lat=this.selectedCoordinates.lat
              lon=this.selectedCoordinates.lon
            }}
          </p>
        {{/if}}
        {{#if this.isReverseGeocoding}}
          <span class="mass-activity-location-map-loading" role="status">
            {{i18n "mass_activity.location_map.loading"}}
          </span>
        {{/if}}
      </div>
      <hr />
      <div class="control-group">
        <label class="control-label">{{i18n "location.name.title"}}</label>
        <div class="controls">
          <Input
            class="input-xxlarge input-location location-name"
            @type="text"
            @value={{this.name}}
          />
        </div>
        <div class="instructions">{{i18n "location.name.desc"}}</div>
      </div>
      <div class="modal-footer">
        <DButton
          class="btn-primary"
          id="save-location"
          @action={{this.submit}}
          @disabled={{this.submitDisabled}}
          @label="location.done"
        />
        <DButton
          class="clear"
          id="clear-location"
          @action={{this.clear}}
          @label="location.clear"
        />
      </div>
    </DModal>
  </template>
}
