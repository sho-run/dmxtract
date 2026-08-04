import init, {
  exportOfl,
  exportGdtf,
  validateFixture,
  fixtureSchema,
} from './wasm/dmxtract_core.js';

const ready = init(new URL('./wasm/dmxtract_core_bg.wasm', import.meta.url));

window.dmxtractCore = {
  async exportOfl(fixtureJson) {
    await ready;
    return exportOfl(fixtureJson);
  },
  async exportGdtf(fixtureJson) {
    await ready;
    return exportGdtf(fixtureJson);
  },
  async validate(fixtureJson) {
    await ready;
    return validateFixture(fixtureJson);
  },
  async schema() {
    await ready;
    return fixtureSchema();
  },
};
