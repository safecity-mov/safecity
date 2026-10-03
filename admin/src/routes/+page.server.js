import { clearDescription, loadHazards, logout, moderate } from '$lib/actions.js';

const PAGE_SIZE = 100;

/** @type {import('./$types').PageServerLoad} */
export const load = (event) => loadHazards(event, PAGE_SIZE);

export const actions = { moderate, clearDescription, logout };
