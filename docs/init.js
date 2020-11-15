import { search as tinysearch, default as init } from "/memo_pub/tinysearch_engine.js";
window.tinysearch = tinysearch;

async function run() {
    await init('/memo_pub/tinysearch_engine_bg.wasm');
}

run();
