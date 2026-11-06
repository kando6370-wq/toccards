import { PGliteDatabase } from "../test-support/pglite-database";
import { createPortfolioPostgresFixture, closePortfolioPostgresFixtures, seedPortfolioRows, readPortfolioRows } from "../test-support/portfolio-postgres-fixture";
import { signAccessToken } from "@kando/auth-core";
import { afterEach, describe, expect, it } from "vitest";
import app, { type Env } from "../index";

type OwnerType = "anonymous" | "user";

type FolderRow = {
  id: string;
  owner_type: OwnerType;
  owner_id: string;
};

type CollectionItemRow = {
  id: string;
  owner_type: OwnerType;
  owner_id: string;
  folder_id: string;
  card_ref: string;
  object_type: string;
  grader: string;
  condition: string | null;
  grade: number | null;
  language: string | null;
  finish: string | null;
  price_series_id: number | null;
  quantity: number;
  purchase_price: number | null;
  purchase_currency: string | null;
  performance_start_at: string;
  purchase_price_effective_at: string;
  performance_history_available_from: string;
  notes: string | null;
  folder_joined_at: string;
  created_at: string;
  updated_at: string;
};

type WishlistRow = {
  owner_type: OwnerType;
  owner_id: string;
  card_ref: string;
};

type CollectionItemEventRow = {
  id: string;
  item_id: string;
  owner_type: OwnerType;
  owner_id: string;
  folder_id: string;
  card_ref: string;
  object_type: string;
  grader: string;
  condition: string | null;
  grade: number | null;
  language: string | null;
  finish: string | null;
  price_series_id: number | null;
  quantity: number;
  purchase_price: number | null;
  purchase_currency: string | null;
  performance_history_available_from: string;
  event_type: "upsert" | "delete";
  effective_at: string;
};

const JWT_SECRET = "test-secret";
const NOW = "2026-07-07T00:00:00.000Z";
const fixtureColumns = {
  wishlist_item: ["owner_type", "owner_id", "card_ref"],
  collection_item_event: ["id", "item_id", "owner_type", "owner_id", "folder_id", "card_ref", "object_type", "grader", "condition", "grade", "language", "finish", "price_series_id", "quantity", "purchase_price", "purchase_currency", "performance_history_available_from", "event_type", "effective_at"],
  collection_item: ["id", "owner_type", "owner_id", "folder_id", "card_ref", "object_type", "grader", "condition", "grade", "language", "finish", "price_series_id", "quantity", "purchase_price", "purchase_currency", "performance_start_at", "purchase_price_effective_at", "performance_history_available_from", "notes", "folder_joined_at", "created_at", "updated_at"],
};

afterEach(async () => { await closePortfolioPostgresFixtures(); });

describe("collection item routes", () => {
  it("creates a Raw collection item and removes the matching wishlist row because Collect transfers intent into ownership", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main" }));
    await seedPortfolioRows(db, 'wishlist_item', { owner_type: "anonymous", owner_id: "anon-1", card_ref: "card-a" });

    const response = await app.request(
      "/api/v1/portfolio/items",
      {
        method: "POST",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({
          folder_id: "main",
          card_ref: "card-a",
          object_type: "tcg",
          grader: "Raw",
          condition: "Near Mint (NM)",
          grade: null,
          language: "English",
          finish: "Holofoil",
          quantity: 2,
          purchase_price: 50,
          purchase_currency: "USD",
          notes: "first copy",
        }),
      },
      createTestEnv(db),
    );

    expect(response.status).toBe(201);
    expect(await response.json()).toEqual({
      success: true,
      data: itemResponse({
        id: expect.any(String),
        folder_id: "main",
        card_ref: "card-a",
        condition: "Near Mint (NM)",
        quantity: 2,
        purchase_price: 50,
        purchase_currency: "USD",
        notes: "first copy",
        created_at: expect.any(String),
        updated_at: expect.any(String),
      }),
    });
    expect((await readPortfolioRows<WishlistRow>(db, 'wishlist_item', fixtureColumns.wishlist_item))).toEqual([]);
    expect((await readPortfolioRows<CollectionItemEventRow>(db, 'collection_item_event', fixtureColumns.collection_item_event))).toEqual([
      expect.objectContaining({
        item_id: expect.any(String),
        folder_id: "main",
        card_ref: "card-a",
        quantity: 2,
        price_series_id: null,
        event_type: "upsert",
      }),
    ]);
  });

  it("replays a lost create response by operation key because retry must confirm the original item", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main" }));
    const idempotencyKey = "33333333-3333-4333-8333-333333333333";
    const headers = {
      ...(await authHeaders("anonymous", "anon-1")),
      "Idempotency-Key": idempotencyKey,
    };
    const body = JSON.stringify({
      folder_id: "main",
      card_ref: "card-a",
      object_type: "tcg",
      grader: "Raw",
      condition: "Near Mint (NM)",
      grade: null,
      language: "English",
      finish: "Holofoil",
      quantity: 2,
      purchase_price: 50,
      purchase_currency: "USD",
      notes: "first copy",
    });

    const created = await app.request(
      "/api/v1/portfolio/items",
      { method: "POST", headers, body },
      createTestEnv(db),
    );
    const replayed = await app.request(
      "/api/v1/portfolio/items",
      { method: "POST", headers, body },
      createTestEnv(db),
    );

    expect(created.status).toBe(201);
    expect(replayed.status).toBe(200);
    expect(await replayed.json()).toMatchObject({
      success: true,
      data: { id: idempotencyKey, card_ref: "card-a", quantity: 2 },
    });
    expect((await readPortfolioRows<CollectionItemRow>(db, 'collection_item', fixtureColumns.collection_item))).toHaveLength(1);
    expect((await readPortfolioRows<CollectionItemEventRow>(db, 'collection_item_event', fixtureColumns.collection_item_event))).toHaveLength(1);
  });

  it("rejects changing an item create after reusing its operation key because one key has one request meaning", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main" }));
    const headers = {
      ...(await authHeaders("anonymous", "anon-1")),
      "Idempotency-Key": "44444444-4444-4444-8444-444444444444",
    };
    const draft = {
      folder_id: "main",
      card_ref: "card-a",
      object_type: "tcg",
      grader: "Raw",
      condition: "Near Mint (NM)",
      grade: null,
      language: "English",
      finish: "Holofoil",
      quantity: 1,
    };
    await app.request(
      "/api/v1/portfolio/items",
      { method: "POST", headers, body: JSON.stringify(draft) },
      createTestEnv(db),
    );

    const response = await app.request(
      "/api/v1/portfolio/items",
      {
        method: "POST",
        headers,
        body: JSON.stringify({ ...draft, quantity: 2 }),
      },
      createTestEnv(db),
    );

    expect(response.status).toBe(409);
    expect((await readPortfolioRows<CollectionItemRow>(db, 'collection_item', fixtureColumns.collection_item))).toHaveLength(1);
  });

  it("rejects the old Raw condition label because raw card condition must use the PRD canonical value", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main" }));

    const response = await app.request(
      "/api/v1/portfolio/items",
      {
        method: "POST",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({
          folder_id: "main",
          card_ref: "card-a",
          object_type: "tcg",
          grader: "Raw",
          condition: "Near Mint",
          grade: null,
          quantity: 1,
        }),
      },
      createTestEnv(db),
    );

    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({
      success: false,
      error: { code: "VALIDATION_ERROR", message: "Invalid request." },
    });
  });

  it("accepts every PRD Raw condition and rejects the deprecated Nearly Mint spelling because raw valuation depends on canonical condition buckets", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main" }));

    for (const condition of [
      "Near Mint (NM)",
      "Lightly Played (LP)",
      "Moderately Played (MP)",
      "Heavily Played (HP)",
      "Damaged (D)",
    ]) {
      const response = await app.request(
        "/api/v1/portfolio/items",
        {
          method: "POST",
          headers: await authHeaders("anonymous", "anon-1"),
          body: JSON.stringify({
            folder_id: "main",
            card_ref: `card-${condition}`,
            object_type: "tcg",
            grader: "Raw",
            condition,
            grade: null,
            quantity: 1,
          }),
        },
        createTestEnv(db),
      );

      expect(response.status).toBe(201);
    }

    const deprecated = await app.request(
      "/api/v1/portfolio/items",
      {
        method: "POST",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({
          folder_id: "main",
          card_ref: "deprecated",
          object_type: "tcg",
          grader: "Raw",
          condition: "Nearly Mint (NM)",
          grade: null,
          quantity: 1,
        }),
      },
      createTestEnv(db),
    );

    expect(deprecated.status).toBe(422);
  });

  it("rejects impossible graded values because grader-specific prices require a valid 1 to 10 grade scale", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main" }));

    const response = await app.request(
      "/api/v1/portfolio/items",
      {
        method: "POST",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({
          folder_id: "main",
          card_ref: "card-a",
          object_type: "tcg",
          grader: "PSA",
          condition: null,
          grade: 10.25,
          quantity: 1,
        }),
      },
      createTestEnv(db),
    );

    expect(response.status).toBe(422);
  });

  it("rejects grader and folder validation failures because collection valuation depends on consistent grading state", async () => {
    const db = await createDbForOwner("user", "user-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main", owner_type: "user", owner_id: "user-1" }));

    const badRaw = await app.request(
      "/api/v1/portfolio/items",
      {
        method: "POST",
        headers: await authHeaders("user", "user-1"),
        body: JSON.stringify({
          folder_id: "main",
          card_ref: "card-a",
          object_type: "tcg",
          grader: "Raw",
          condition: null,
          grade: null,
          quantity: 1,
        }),
      },
      createTestEnv(db),
    );
    const missingFolder = await app.request(
      "/api/v1/portfolio/items",
      {
        method: "POST",
        headers: await authHeaders("user", "user-1"),
        body: JSON.stringify({
          folder_id: "missing",
          card_ref: "card-a",
          object_type: "tcg",
          grader: "PSA",
          condition: null,
          grade: 9,
          quantity: 1,
        }),
      },
      createTestEnv(db),
    );

    expect(badRaw.status).toBe(422);
    expect(await badRaw.json()).toEqual({
      success: false,
      error: { code: "VALIDATION_ERROR", message: "Invalid request." },
    });
    expect(missingFolder.status).toBe(404);
    expect(await missingFolder.json()).toEqual({
      success: false,
      error: { code: "NOT_FOUND", message: "Not found." },
    });
  });

  it("allows the same card variant and grade when the grader differs", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main" }));
    await seedPortfolioRows(db, 'collection_item', item({
      id: "owned",
      folder_id: "main",
      card_ref: "card-a",
      grader: "PSA",
      condition: null,
      grade: 10,
    }));

    const response = await app.request("/api/v1/portfolio/items", {
      method: "POST",
      headers: await authHeaders("anonymous", "anon-1"),
      body: JSON.stringify({
        folder_id: "main", card_ref: "card-a", object_type: "tcg", grader: "BGS",
        condition: null, grade: 10, language: "English",
        finish: "Holofoil", quantity: 1,
      }),
    }, createTestEnv(db));

    expect(response.status).toBe(201);
    expect((await readPortfolioRows<CollectionItemRow>(db, 'collection_item', fixtureColumns.collection_item))).toHaveLength(2);
  });

  it("allows the same graded card variant when the grade differs", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main" }));
    await seedPortfolioRows(db, 'collection_item', item({
      id: "owned",
      folder_id: "main",
      card_ref: "card-a",
      grader: "PSA",
      condition: null,
      grade: 9,
    }));

    const response = await app.request("/api/v1/portfolio/items", {
      method: "POST",
      headers: await authHeaders("anonymous", "anon-1"),
      body: JSON.stringify({
        folder_id: "main", card_ref: "card-a", object_type: "tcg", grader: "PSA",
        condition: null, grade: 10, language: "English",
        finish: "Holofoil", quantity: 1,
      }),
    }, createTestEnv(db));

    expect(response.status).toBe(201);
    expect((await readPortfolioRows<CollectionItemRow>(db, 'collection_item', fixtureColumns.collection_item))).toHaveLength(2);
  });

  it("allows the same Raw card variant when the condition differs", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main" }));
    await seedPortfolioRows(db, 'collection_item', item({ id: "owned", folder_id: "main", card_ref: "card-a" }));

    const response = await app.request("/api/v1/portfolio/items", {
      method: "POST",
      headers: await authHeaders("anonymous", "anon-1"),
      body: JSON.stringify({
        folder_id: "main", card_ref: "card-a", object_type: "tcg", grader: "Raw",
        condition: "Lightly Played (LP)", grade: null, language: "English",
        finish: "Holofoil", quantity: 1,
      }),
    }, createTestEnv(db));

    expect(response.status).toBe(201);
    expect((await readPortfolioRows<CollectionItemRow>(db, 'collection_item', fixtureColumns.collection_item))).toHaveLength(2);
  });

  it("preserves folder join time during field-only edits because ordinary edits are not folder additions", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main" }));
    await seedPortfolioRows(db, 'collection_item', item({ id: "owned", folder_id: "main", price_series_id: 7 }));

    const response = await app.request(
      "/api/v1/portfolio/items/owned",
      {
        method: "PATCH",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({ quantity: 2, notes: "edited in place" }),
      },
      createTestEnv(db),
    );

    expect(response.status).toBe(200);
    expect((await readPortfolioRows<CollectionItemRow>(db, 'collection_item', fixtureColumns.collection_item))[0].quantity).toBe(2);
    expect((await readPortfolioRows<CollectionItemRow>(db, 'collection_item', fixtureColumns.collection_item))[0].price_series_id).toBe(7);
    expect((await readPortfolioRows<CollectionItemRow>(db, 'collection_item', fixtureColumns.collection_item))[0].folder_joined_at).toBe(NOW);
    expect((await readPortfolioRows<CollectionItemRow>(db, 'collection_item', fixtureColumns.collection_item))[0].updated_at).not.toBe(NOW);
    expect((await readPortfolioRows<CollectionItemEventRow>(db, 'collection_item_event', fixtureColumns.collection_item_event))[0]?.price_series_id).toBe(7);
  });

  it("rejects an edit that would duplicate another collection item identity", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main" }));
    await seedPortfolioRows(db, 'collection_item', item({ id: "existing" }), item({ id: "edited", condition: "Lightly Played (LP)" }));

    const response = await app.request(
      "/api/v1/portfolio/items/edited",
      {
        method: "PATCH",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({ condition: "Near Mint (NM)" }),
      },
      createTestEnv(db),
    );

    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({
      success: false,
      error: {
        code: "DUPLICATE_COLLECTION_ITEM",
        message:
          "This card with the same finish, language, and grading is already in this portfolio.",
      },
    });

    expect((await readPortfolioRows<CollectionItemRow>(db, 'collection_item', fixtureColumns.collection_item)).find((row) => row.id === "edited")?.condition).toBe(
      "Lightly Played (LP)",
    );
    expect((await readPortfolioRows<CollectionItemEventRow>(db, 'collection_item_event', fixtureColumns.collection_item_event))).toEqual([]);
  });

  it("maps a concurrent PostgreSQL duplicate during edit to the existing duplicate response", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main" }));
    await seedPortfolioRows(db, 'collection_item', item({ id: "edited", condition: "Lightly Played (LP)" }));
    await db.exec(`CREATE FUNCTION fixture_concurrent_duplicate() RETURNS trigger
      LANGUAGE plpgsql AS $$ BEGIN
        RAISE EXCEPTION 'duplicate key value violates unique constraint "uq_collection_item_folder_card_variant"'
          USING ERRCODE = '23505', CONSTRAINT = 'uq_collection_item_folder_card_variant';
      END $$;
      CREATE TRIGGER fixture_concurrent_duplicate BEFORE UPDATE ON collection_item
      FOR EACH ROW EXECUTE FUNCTION fixture_concurrent_duplicate();`);

    const response = await app.request(
      "/api/v1/portfolio/items/edited",
      {
        method: "PATCH",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({ condition: "Near Mint (NM)" }),
      },
      createTestEnv(db),
    );

    expect(response.status).toBe(409);
    expect(await response.json()).toMatchObject({
      error: { code: "DUPLICATE_COLLECTION_ITEM" },
    });

    expect((await readPortfolioRows<CollectionItemRow>(db, 'collection_item', fixtureColumns.collection_item))[0].condition).toBe("Lightly Played (LP)");
    expect((await readPortfolioRows<CollectionItemEventRow>(db, 'collection_item_event', fixtureColumns.collection_item_event))).toEqual([]);
  });

  it("edits fields and moves folders in one PATCH because edited moves must complete atomically", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main" }), folder({ id: "trade" }));
    await seedPortfolioRows(db, 'collection_item', item({ id: "owned", folder_id: "main", price_series_id: 7 }));

    const response = await app.request(
      "/api/v1/portfolio/items/owned",
      {
        method: "PATCH",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({
          folder_id: "trade",
          grader: "PSA",
          condition: null,
          grade: 10,
          quantity: 2,
          notes: "trade binder",
        }),
      },
      createTestEnv(db),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      success: true,
      data: itemResponse({
        id: "owned",
        folder_id: "trade",
        grader: "PSA",
        condition: null,
        grade: 10,
        quantity: 2,
        notes: "trade binder",
        updated_at: expect.any(String),
      }),
    });

    expect((await readPortfolioRows<CollectionItemRow>(db, 'collection_item', fixtureColumns.collection_item))).toEqual([
      expect.objectContaining({
        id: "owned",
        folder_id: "trade",
        grader: "PSA",
        grade: 10,
        price_series_id: null,
        quantity: 2,
        notes: "trade binder",
      }),
    ]);
    expect((await readPortfolioRows<CollectionItemRow>(db, 'collection_item', fixtureColumns.collection_item))[0].folder_joined_at).toBe((await readPortfolioRows<CollectionItemRow>(db, 'collection_item', fixtureColumns.collection_item))[0].updated_at);
    expect((await readPortfolioRows<CollectionItemRow>(db, 'collection_item', fixtureColumns.collection_item))[0].folder_joined_at).not.toBe(NOW);
    expect((await readPortfolioRows<CollectionItemEventRow>(db, 'collection_item_event', fixtureColumns.collection_item_event))).toEqual([
      expect.objectContaining({
        item_id: "owned",
        folder_id: "trade",
        grader: "PSA",
        grade: 10,
        price_series_id: null,
        quantity: 2,
        event_type: "upsert",
      }),
    ]);
  });

  it("keeps the original folder when an edited move targets another owner because failed saves must not move assets", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main" }), folder({ id: "private", owner_type: "user", owner_id: "user-2" }));
    await seedPortfolioRows(db, 'collection_item', item({ id: "owned", folder_id: "main" }));

    const response = await app.request(
      "/api/v1/portfolio/items/owned",
      {
        method: "PATCH",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({ folder_id: "private", quantity: 2 }),
      },
      createTestEnv(db),
    );

    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({
      success: false,
      error: { code: "NOT_FOUND", message: "Not found." },
    });

    expect((await readPortfolioRows<CollectionItemRow>(db, 'collection_item', fixtureColumns.collection_item))).toEqual([
      expect.objectContaining({
        id: "owned",
        folder_id: "main",
        quantity: 1,
      }),
    ]);
    expect((await readPortfolioRows<CollectionItemEventRow>(db, 'collection_item_event', fixtureColumns.collection_item_event))).toEqual([]);
  });

  it("preserves a saved series in move and delete events because folder changes must not rewrite historical pricing", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main" }), folder({ id: "trade" }));
    await seedPortfolioRows(db, 'collection_item', item({ id: "owned", folder_id: "main", price_series_id: 7 }));
    const headers = await authHeaders("anonymous", "anon-1");

    const move = await app.request(
      "/api/v1/portfolio/items/owned/move",
      { method: "PATCH", headers, body: JSON.stringify({ folder_id: "trade" }) },
      createTestEnv(db),
    );
    const remove = await app.request(
      "/api/v1/portfolio/items/owned",
      { method: "DELETE", headers },
      createTestEnv(db),
    );

    expect(move.status).toBe(200);
    expect(remove.status).toBe(200);
    expect((await readPortfolioRows<CollectionItemEventRow>(db, 'collection_item_event', fixtureColumns.collection_item_event)).map((eventRow) => eventRow.price_series_id)).toEqual([7, 7]);
  });

  it("gets, updates, moves, and deletes only owned collection items because item operations must stay inside the owner boundary", async () => {
    const db = await createDbForOwner("anonymous", "anon-1");
    await seedPortfolioRows(db, 'portfolio_folder', folder({ id: "main" }), folder({ id: "trade" }));
    await seedPortfolioRows(db, 'collection_item', item({ id: "owned", folder_id: "main" }));

    const detail = await app.request(
      "/api/v1/portfolio/items/owned",
      { headers: await authHeaders("anonymous", "anon-1") },
      createTestEnv(db),
    );
    const update = await app.request(
      "/api/v1/portfolio/items/owned",
      {
        method: "PATCH",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({
          grader: "PSA",
          grade: 10,
          condition: null,
          language: "Japanese",
          finish: "Foil",
          quantity: 3,
          purchase_price: null,
          purchase_currency: null,
          notes: "graded",
        }),
      },
      createTestEnv(db),
    );
    const move = await app.request(
      "/api/v1/portfolio/items/owned/move",
      {
        method: "PATCH",
        headers: await authHeaders("anonymous", "anon-1"),
        body: JSON.stringify({ folder_id: "trade" }),
      },
      createTestEnv(db),
    );
    const remove = await app.request(
      "/api/v1/portfolio/items/owned",
      {
        method: "DELETE",
        headers: await authHeaders("anonymous", "anon-1"),
      },
      createTestEnv(db),
    );

    expect(detail.status).toBe(200);
    expect(await detail.json()).toEqual({
      success: true,
      data: itemResponse({ id: "owned", folder_id: "main" }),
    });
    expect(update.status).toBe(200);
    expect(await update.json()).toEqual({
      success: true,
      data: itemResponse({
        id: "owned",
        folder_id: "main",
        grader: "PSA",
        condition: null,
        grade: 10,
        language: "Japanese",
        finish: "Foil",
        quantity: 3,
        notes: "graded",
        updated_at: expect.any(String),
      }),
    });
    expect(move.status).toBe(200);
    expect(await move.json()).toEqual({
      success: true,
      data: itemResponse({
        id: "owned",
        folder_id: "trade",
        grader: "PSA",
        condition: null,
        grade: 10,
        language: "Japanese",
        finish: "Foil",
        quantity: 3,
        notes: "graded",
        updated_at: expect.any(String),
      }),
    });
    expect(remove.status).toBe(200);
    expect(await remove.json()).toEqual({ success: true, data: {} });
    expect((await readPortfolioRows<CollectionItemRow>(db, 'collection_item', fixtureColumns.collection_item))).toEqual([]);
    expect((await readPortfolioRows<CollectionItemEventRow>(db, 'collection_item_event', fixtureColumns.collection_item_event))).toEqual([
      expect.objectContaining({
        item_id: "owned",
        folder_id: "main",
        grader: "PSA",
        quantity: 3,
        event_type: "upsert",
      }),
      expect.objectContaining({
        item_id: "owned",
        folder_id: "trade",
        grader: "PSA",
        quantity: 3,
        event_type: "upsert",
      }),
      expect.objectContaining({
        item_id: "owned",
        folder_id: "trade",
        grader: "PSA",
        quantity: 3,
        event_type: "delete",
      }),
    ]);
  });
});

async function createDbForOwner(ownerType: OwnerType, ownerId: string): Promise<PGliteDatabase> {
  return createPortfolioPostgresFixture(ownerType, ownerId);
}

function createTestEnv(db: PGliteDatabase): Env {
  return { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET };
}

async function authHeaders(
  ownerType: OwnerType,
  ownerId: string,
): Promise<{ Authorization: string; "Content-Type": string }> {
  const token = await signAccessToken(
    {
      owner_type: ownerType,
      owner_id: ownerId,
      session_id: sessionId(ownerType, ownerId),
    },
    JWT_SECRET,
  );

  return { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
}

function sessionId(ownerType: OwnerType, ownerId: string): string {
  return `${ownerType}-${ownerId}-session`;
}

function folder(overrides: Partial<FolderRow>): FolderRow {
  return {
    id: "main",
    owner_type: "anonymous",
    owner_id: "anon-1",
    ...overrides,
  };
}

function item(overrides: Partial<CollectionItemRow>): CollectionItemRow {
  return {
    id: "item",
    owner_type: "anonymous",
    owner_id: "anon-1",
    folder_id: "main",
    card_ref: "card-a",
    object_type: "tcg",
    grader: "Raw",
    condition: "Near Mint (NM)",
    grade: null,
    language: "English",
    finish: "Holofoil",
    price_series_id: null,
    quantity: 1,
    purchase_price: null,
    purchase_currency: null,
    performance_start_at: NOW,
    purchase_price_effective_at: NOW,
    performance_history_available_from: NOW,
    notes: null,
    folder_joined_at: NOW,
    created_at: NOW,
    updated_at: NOW,
    ...overrides,
  };
}

function itemResponse(
  overrides: Partial<{
    id: unknown;
    folder_id: string;
    card_ref: string;
    object_type: string;
    grader: string;
    condition: string | null;
    grade: number | null;
    language: string | null;
    finish: string | null;
    quantity: number;
    purchase_price: number | null;
    purchase_currency: string | null;
    notes: string | null;
    created_at: unknown;
    updated_at: unknown;
  }>,
): {
  id: unknown;
  folder_id: string;
  card_ref: string;
  object_type: string;
  grader: string;
  condition: string | null;
  grade: number | null;
  language: string | null;
  finish: string | null;
  quantity: number;
  purchase_price: number | null;
  purchase_currency: string | null;
  notes: string | null;
  created_at: unknown;
  updated_at: unknown;
} {
  return {
    id: "item",
    folder_id: "main",
    card_ref: "card-a",
    object_type: "tcg",
    grader: "Raw",
    condition: "Near Mint (NM)",
    grade: null,
    language: "English",
    finish: "Holofoil",
    quantity: 1,
    purchase_price: null,
    purchase_currency: null,
    notes: null,
    created_at: NOW,
    updated_at: NOW,
    ...overrides,
  };
}
