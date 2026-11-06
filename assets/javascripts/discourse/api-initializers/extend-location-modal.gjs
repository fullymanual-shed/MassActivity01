import { action } from "@ember/object";
import { apiInitializer } from "discourse/lib/api";
import classPrepend from "discourse/lib/class-prepend";
import AddLocationControls from "discourse/plugins/discourse-locations/discourse/components/add-location-controls";
import AddLocationMapModal from "../components/modal/add-location-map.gjs";

export default apiInitializer(() => {
  classPrepend(
    AddLocationControls,
    (Superclass) =>
      class extends Superclass {
        @action
        showAddLocation() {
          return this.modal.show(AddLocationMapModal, {
            model: {
              location: this.args.location,
              categoryId: this.args.category.id,
              update: (location) => {
                if (this._state !== "destroying") {
                  this.args.updateLocation(location);
                }
              },
            },
          });
        }
      }
  );
});
