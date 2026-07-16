import { Hono } from "hono";
import {
  collectionItemDraftFromBody,
  collectionItemPatchFromBody,
  type CollectionItemDraft,
} from "../collection-item";
import type { Env } from "../env";
import { createId } from "../id";
import { authenticateOwner, type AuthenticatedOwner } from "../owner-auth";

type PortfolioFolderRow = {
  id: string;
  name: string;
  is_default: number;
  sort_order: number;
  created_at: string;
  updated_at: string;
};

type FolderOrder = {
  folder_id: string;
  sort_order: number;
};

type CollectionItemRow = {
  id: string;
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
  created_at: string;
  updated_at: string;
};

type WishlistItemRow = {
  id: string;
  card_ref: string;
  created_at: string;
};

type UserPreferenceRow = {
  id: string;
  currency: string;
  amount_hidden: number;
  last_selected_folder_id: string | null;
  created_at: string;
  updated_at: string;
};

type UserPreferencePatch = {
  currency: string;
  amount_hidden: number;
  last_selected_folder_id: string | null;
  folder_id_to_validate: string | null;
};

const UNAUTHORIZED_RESPONSE = {
  success: false,
  error: { code: "UNAUTHORIZED", message: "Unauthorized." },
} as const;

const VALIDATION_ERROR_RESPONSE = {
  success: false,
  error: { code: "VALIDATION_ERROR", message: "Invalid request." },
} as const;

const NOT_FOUND_RESPONSE = {
  success: false,
  error: { code: "NOT_FOUND", message: "Not found." },
} as const;

const FORBIDDEN_RESPONSE = {
  success: false,
  error: { code: "FORBIDDEN", message: "Forbidden." },
} as const;

const CONFLICT_RESPONSE = {
  success: false,
  error: { code: "CONFLICT", message: "Conflict." },
} as const;

const INTERNAL_ERROR_RESPONSE = {
  success: false,
  error: {
    code: "INTERNAL_ERROR",
    message: "Something went wrong. Please try again.",
  },
} as const;

const SELECT_FOLDERS_SQL = `
SELECT id, name, is_default, sort_order, created_at, updated_at
FROM portfolio_folder
WHERE owner_type = ? AND owner_id = ?
ORDER BY sort_order ASC
`;

const SELECT_FOLDER_SQL = `
SELECT id, name, is_default, sort_order, created_at, updated_at
FROM portfolio_folder
WHERE owner_type = ? AND owner_id = ? AND id = ?
LIMIT 1
`;

const SELECT_DEFAULT_FOLDER_SQL = `
SELECT id, name, is_default, sort_order, created_at, updated_at
FROM portfolio_folder
WHERE owner_type = ? AND owner_id = ? AND is_default = 1
LIMIT 1
`;

const INSERT_FOLDER_SQL = `
INSERT INTO portfolio_folder
  (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
VALUES (?, ?, ?, ?, 0, ?, ?, ?)
`;

const UPDATE_FOLDER_NAME_SQL = `
UPDATE portfolio_folder
SET name = ?, updated_at = ?
WHERE owner_type = ? AND owner_id = ? AND id = ?
`;

const DELETE_FOLDER_SQL = `
DELETE FROM portfolio_folder
WHERE owner_type = ? AND owner_id = ? AND id = ?
`;

const CLEAR_LAST_SELECTED_FOLDER_SQL = `
UPDATE user_preference
SET last_selected_folder_id = NULL
WHERE owner_type = ? AND owner_id = ? AND last_selected_folder_id = ?
`;

const CLEAR_DEFAULT_FOLDERS_SQL = `
UPDATE portfolio_folder
SET is_default = 0, updated_at = ?
WHERE owner_type = ? AND owner_id = ?
`;

const SET_DEFAULT_FOLDER_SQL = `
UPDATE portfolio_folder
SET is_default = 1, updated_at = ?
WHERE owner_type = ? AND owner_id = ? AND id = ?
`;

const UPDATE_FOLDER_SORT_ORDER_SQL = `
UPDATE portfolio_folder
SET sort_order = ?, updated_at = ?
WHERE owner_type = ? AND owner_id = ? AND id = ?
`;

const SELECT_COLLECTION_ITEMS_SQL = `
SELECT id, folder_id, card_ref, object_type, grader, condition, grade, language,
  finish, quantity, purchase_price, purchase_currency, notes, created_at, updated_at
FROM collection_item
WHERE owner_type = ? AND owner_id = ?
`;

const SELECT_COLLECTION_ITEM_SQL = `
SELECT id, folder_id, card_ref, object_type, grader, condition, grade, language,
  finish, quantity, purchase_price, purchase_currency, notes, created_at, updated_at
FROM collection_item
WHERE owner_type = ? AND owner_id = ? AND id = ?
LIMIT 1
`;

const SELECT_COLLECTION_ITEM_BY_CARD_SQL = `
SELECT id, folder_id, card_ref, object_type, grader, condition, grade, language,
  finish, quantity, purchase_price, purchase_currency, notes, created_at, updated_at
FROM collection_item
WHERE owner_type = ? AND owner_id = ? AND card_ref = ?
LIMIT 1
`;

const INSERT_COLLECTION_ITEM_SQL = `
INSERT INTO collection_item
  (id, owner_type, owner_id, folder_id, card_ref, object_type, grader, condition,
   grade, language, finish, quantity, purchase_price, purchase_currency, notes,
   created_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
`;

const UPDATE_COLLECTION_ITEM_SQL = `
UPDATE collection_item
SET grader = ?, condition = ?, grade = ?, language = ?, finish = ?, quantity = ?,
  purchase_price = ?, purchase_currency = ?, notes = ?, updated_at = ?
WHERE owner_type = ? AND owner_id = ? AND id = ?
`;

const MOVE_COLLECTION_ITEM_SQL = `
UPDATE collection_item
SET folder_id = ?, updated_at = ?
WHERE owner_type = ? AND owner_id = ? AND id = ?
`;

const DELETE_COLLECTION_ITEM_SQL = `
DELETE FROM collection_item
WHERE owner_type = ? AND owner_id = ? AND id = ?
`;

const INSERT_COLLECTION_ITEM_EVENT_SQL = `
INSERT INTO collection_item_event
  (id, item_id, owner_type, owner_id, folder_id, card_ref, object_type, grader,
   condition, grade, language, finish, quantity, event_type, effective_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
`;

const DELETE_WISHLIST_CARD_SQL = `
DELETE FROM wishlist_item
WHERE owner_type = ? AND owner_id = ? AND card_ref = ?
`;

const SELECT_WISHLIST_ITEMS_SQL = `
SELECT id, card_ref, created_at
FROM wishlist_item
WHERE owner_type = ? AND owner_id = ?
`;

const SELECT_WISHLIST_ITEM_SQL = `
SELECT id, card_ref, created_at
FROM wishlist_item
WHERE owner_type = ? AND owner_id = ? AND id = ?
LIMIT 1
`;

const INSERT_WISHLIST_ITEM_SQL = `
INSERT INTO wishlist_item
  (id, owner_type, owner_id, card_ref, created_at)
VALUES (?, ?, ?, ?, ?)
`;

const DELETE_WISHLIST_ITEM_SQL = `
DELETE FROM wishlist_item
WHERE owner_type = ? AND owner_id = ? AND id = ?
`;

const SELECT_USER_PREFERENCE_SQL = `
SELECT id, currency, amount_hidden, last_selected_folder_id, created_at, updated_at
FROM user_preference
WHERE owner_type = ? AND owner_id = ?
LIMIT 1
`;

const UPDATE_USER_PREFERENCE_SQL = `
UPDATE user_preference
SET currency = ?, amount_hidden = ?, last_selected_folder_id = ?, updated_at = ?
WHERE owner_type = ? AND owner_id = ?
`;

const ITEM_SORT_FIELDS = new Set(["created_at", "updated_at", "card_ref"]);
const WISHLIST_SORT_FIELDS = new Set(["created_at", "card_ref"]);
const ISO_4217_CURRENCY_PATTERN = /^[A-Z]{3}$/;

export function createPortfolioRoutes(): Hono<{ Bindings: Env }> {
  const routes = new Hono<{ Bindings: Env }>();

  routes.post("/cards/:card_ref/collect", async (c) => {
    const auth = await authenticateOwner(
      c.env,
      c.req.header("Authorization"),
    );

    if (auth.status === "internal_error") {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    if (auth.status === "unauthorized") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const cardRef = requiredString(c.req.param("card_ref"));
    const body = await readJson(c.req);

    if (!cardRef || !isRecord(body)) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    const requestedFolderId = collectFolderIdFromBody(body);

    if (requestedFolderId === undefined) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    const folder = requestedFolderId
      ? await findFolder(c.env.DB, auth.owner, requestedFolderId)
      : await findDefaultFolder(c.env.DB, auth.owner);

    if (!folder) {
      return c.json(NOT_FOUND_RESPONSE, 404);
    }

    const draft = collectItemDraftFromBody(body, cardRef, folder.id);

    if (!draft) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    const now = new Date().toISOString();
    const itemId = createId();

    await c.env.DB.batch([
      c.env.DB.prepare(INSERT_COLLECTION_ITEM_SQL).bind(
        itemId,
        auth.owner.owner_type,
        auth.owner.owner_id,
        draft.folder_id,
        draft.card_ref,
        draft.object_type,
        draft.grader,
        draft.condition,
        draft.grade,
        draft.language,
        draft.finish,
        draft.quantity,
        draft.purchase_price,
        draft.purchase_currency,
        draft.notes,
        now,
        now,
      ),
      collectionItemEventStatement(c.env.DB, auth.owner, {
        id: itemId,
        ...draft,
        created_at: now,
        updated_at: now,
      }, "upsert", now),
      c.env.DB.prepare(DELETE_WISHLIST_CARD_SQL).bind(
        auth.owner.owner_type,
        auth.owner.owner_id,
        draft.card_ref,
      ),
    ]);

    const item = await findCollectionItem(c.env.DB, auth.owner, itemId);

    return c.json({ success: true, data: collectionItemResponse(item!) }, 201);
  });

  routes.get("/preferences", async (c) => {
    const auth = await authenticateOwner(
      c.env,
      c.req.header("Authorization"),
    );

    if (auth.status === "internal_error") {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    if (auth.status === "unauthorized") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const preference = await findUserPreference(c.env.DB, auth.owner);

    return preference
      ? c.json({ success: true, data: userPreferenceResponse(preference) })
      : c.json(NOT_FOUND_RESPONSE, 404);
  });

  routes.patch("/preferences", async (c) => {
    const auth = await authenticateOwner(
      c.env,
      c.req.header("Authorization"),
    );

    if (auth.status === "internal_error") {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    if (auth.status === "unauthorized") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const preference = await findUserPreference(c.env.DB, auth.owner);

    if (!preference) {
      return c.json(NOT_FOUND_RESPONSE, 404);
    }

    const patch = userPreferencePatchFromBody(await readJson(c.req), preference);

    if (!patch) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    if (
      patch.folder_id_to_validate &&
      !(await findFolder(c.env.DB, auth.owner, patch.folder_id_to_validate))
    ) {
      return c.json(NOT_FOUND_RESPONSE, 404);
    }

    await c.env.DB.prepare(UPDATE_USER_PREFERENCE_SQL)
      .bind(
        patch.currency,
        patch.amount_hidden,
        patch.last_selected_folder_id,
        new Date().toISOString(),
        auth.owner.owner_type,
        auth.owner.owner_id,
      )
      .run();

    const updatedPreference = await findUserPreference(c.env.DB, auth.owner);

    return c.json({
      success: true,
      data: userPreferenceResponse(updatedPreference!),
    });
  });

  routes.get("/wishlist", async (c) => {
    const auth = await authenticateOwner(
      c.env,
      c.req.header("Authorization"),
    );

    if (auth.status === "internal_error") {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    if (auth.status === "unauthorized") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const page = positiveIntegerOrDefault(c.req.query("page"), 1);
    const pageSize = positiveIntegerOrDefault(c.req.query("page_size"), 20, 100);
    const sortBy = wishlistSortBy(c.req.query("sort_by"));
    const sortOrder = c.req.query("sort_order") === "asc" ? "asc" : "desc";
    const items = await listWishlistItems(c.env.DB, auth.owner);
    const sortedItems = sortWishlistItems(items, sortBy, sortOrder);
    const startIndex = (page - 1) * pageSize;

    return c.json({
      success: true,
      data: {
        items: sortedItems
          .slice(startIndex, startIndex + pageSize)
          .map(wishlistItemResponse),
        total: sortedItems.length,
        page,
        page_size: pageSize,
      },
    });
  });

  routes.post("/wishlist", async (c) => {
    const auth = await authenticateOwner(
      c.env,
      c.req.header("Authorization"),
    );

    if (auth.status === "internal_error") {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    if (auth.status === "unauthorized") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const cardRef = wishlistCardRefFromBody(await readJson(c.req));

    if (!cardRef) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    const existingCollectionItem = await findCollectionItemByCard(
      c.env.DB,
      auth.owner,
      cardRef,
    );

    if (existingCollectionItem) {
      return c.json(CONFLICT_RESPONSE, 409);
    }

    const now = new Date().toISOString();
    const itemId = createId();

    try {
      await c.env.DB.prepare(INSERT_WISHLIST_ITEM_SQL)
        .bind(itemId, auth.owner.owner_type, auth.owner.owner_id, cardRef, now)
        .run();
    } catch (error) {
      if (isUniqueConstraintError(error)) {
        return c.json(CONFLICT_RESPONSE, 409);
      }

      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    const item = await findWishlistItem(c.env.DB, auth.owner, itemId);

    return c.json({ success: true, data: wishlistItemResponse(item!) }, 201);
  });

  routes.delete("/wishlist/:item_id", async (c) => {
    const auth = await authenticateOwner(
      c.env,
      c.req.header("Authorization"),
    );

    if (auth.status === "internal_error") {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    if (auth.status === "unauthorized") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const item = await findWishlistItem(c.env.DB, auth.owner, c.req.param("item_id"));

    if (!item) {
      return c.json(NOT_FOUND_RESPONSE, 404);
    }

    await c.env.DB.prepare(DELETE_WISHLIST_ITEM_SQL)
      .bind(auth.owner.owner_type, auth.owner.owner_id, c.req.param("item_id"))
      .run();

    return c.json({ success: true, data: {} });
  });

  routes.get("/portfolio/items", async (c) => {
    const auth = await authenticateOwner(
      c.env,
      c.req.header("Authorization"),
    );

    if (auth.status === "internal_error") {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    if (auth.status === "unauthorized") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const folderId = nullableString(c.req.query("folder_id"));
    const page = positiveIntegerOrDefault(c.req.query("page"), 1);
    const pageSize = positiveIntegerOrDefault(c.req.query("page_size"), 20, 100);
    const sortBy = itemSortBy(c.req.query("sort_by"));
    const sortOrder = c.req.query("sort_order") === "asc" ? "asc" : "desc";
    const allItems = await listCollectionItems(c.env.DB, auth.owner);
    const filteredItems = folderId
      ? allItems.filter((item) => item.folder_id === folderId)
      : allItems;
    const sortedItems = sortCollectionItems(filteredItems, sortBy, sortOrder);
    const startIndex = (page - 1) * pageSize;

    return c.json({
      success: true,
      data: {
        items: sortedItems
          .slice(startIndex, startIndex + pageSize)
          .map(collectionItemResponse),
        total: sortedItems.length,
        page,
        page_size: pageSize,
      },
    });
  });

  routes.post("/portfolio/items", async (c) => {
    const auth = await authenticateOwner(
      c.env,
      c.req.header("Authorization"),
    );

    if (auth.status === "internal_error") {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    if (auth.status === "unauthorized") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const draft = collectionItemDraftFromBody(await readJson(c.req));

    if (!draft) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    const folder = await findFolder(c.env.DB, auth.owner, draft.folder_id);

    if (!folder) {
      return c.json(NOT_FOUND_RESPONSE, 404);
    }

    const now = new Date().toISOString();
    const itemId = createId();

    await c.env.DB.batch([
      c.env.DB.prepare(INSERT_COLLECTION_ITEM_SQL).bind(
        itemId,
        auth.owner.owner_type,
        auth.owner.owner_id,
        draft.folder_id,
        draft.card_ref,
        draft.object_type,
        draft.grader,
        draft.condition,
        draft.grade,
        draft.language,
        draft.finish,
        draft.quantity,
        draft.purchase_price,
        draft.purchase_currency,
        draft.notes,
        now,
        now,
      ),
      collectionItemEventStatement(c.env.DB, auth.owner, {
        id: itemId,
        ...draft,
        created_at: now,
        updated_at: now,
      }, "upsert", now),
      c.env.DB.prepare(DELETE_WISHLIST_CARD_SQL).bind(
        auth.owner.owner_type,
        auth.owner.owner_id,
        draft.card_ref,
      ),
    ]);

    const item = await findCollectionItem(c.env.DB, auth.owner, itemId);

    return c.json({ success: true, data: collectionItemResponse(item!) }, 201);
  });

  routes.get("/portfolio/items/:item_id", async (c) => {
    const auth = await authenticateOwner(
      c.env,
      c.req.header("Authorization"),
    );

    if (auth.status === "internal_error") {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    if (auth.status === "unauthorized") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const item = await findCollectionItem(c.env.DB, auth.owner, c.req.param("item_id"));

    return item
      ? c.json({ success: true, data: collectionItemResponse(item) })
      : c.json(NOT_FOUND_RESPONSE, 404);
  });

  routes.patch("/portfolio/items/:item_id/move", async (c) => {
    const auth = await authenticateOwner(
      c.env,
      c.req.header("Authorization"),
    );

    if (auth.status === "internal_error") {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    if (auth.status === "unauthorized") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const body = await readJson(c.req);
    const folderId = isRecord(body) ? requiredString(body.folder_id) : null;
    const item = await findCollectionItem(c.env.DB, auth.owner, c.req.param("item_id"));

    if (!folderId) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    if (!item) {
      return c.json(NOT_FOUND_RESPONSE, 404);
    }

    const folder = await findFolder(c.env.DB, auth.owner, folderId);

    if (!folder) {
      return c.json(NOT_FOUND_RESPONSE, 404);
    }

    const now = new Date().toISOString();
    await c.env.DB.batch([
      c.env.DB.prepare(MOVE_COLLECTION_ITEM_SQL).bind(
        folderId,
        now,
        auth.owner.owner_type,
        auth.owner.owner_id,
        item.id,
      ),
      collectionItemEventStatement(
        c.env.DB,
        auth.owner,
        { ...item, folder_id: folderId, updated_at: now },
        "upsert",
        now,
      ),
    ]);

    const updatedItem = await findCollectionItem(c.env.DB, auth.owner, item.id);

    return c.json({ success: true, data: collectionItemResponse(updatedItem!) });
  });

  routes.patch("/portfolio/items/:item_id", async (c) => {
    const auth = await authenticateOwner(
      c.env,
      c.req.header("Authorization"),
    );

    if (auth.status === "internal_error") {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    if (auth.status === "unauthorized") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const item = await findCollectionItem(c.env.DB, auth.owner, c.req.param("item_id"));

    if (!item) {
      return c.json(NOT_FOUND_RESPONSE, 404);
    }

    const draft = collectionItemPatchFromBody(await readJson(c.req), item);

    if (!draft) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    const now = new Date().toISOString();
    await c.env.DB.batch([
      c.env.DB.prepare(UPDATE_COLLECTION_ITEM_SQL).bind(
        draft.grader,
        draft.condition,
        draft.grade,
        draft.language,
        draft.finish,
        draft.quantity,
        draft.purchase_price,
        draft.purchase_currency,
        draft.notes,
        now,
        auth.owner.owner_type,
        auth.owner.owner_id,
        item.id,
      ),
      collectionItemEventStatement(
        c.env.DB,
        auth.owner,
        { ...item, ...draft, updated_at: now },
        "upsert",
        now,
      ),
    ]);

    const updatedItem = await findCollectionItem(c.env.DB, auth.owner, item.id);

    return c.json({ success: true, data: collectionItemResponse(updatedItem!) });
  });

  routes.delete("/portfolio/items/:item_id", async (c) => {
    const auth = await authenticateOwner(
      c.env,
      c.req.header("Authorization"),
    );

    if (auth.status === "internal_error") {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    if (auth.status === "unauthorized") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const item = await findCollectionItem(c.env.DB, auth.owner, c.req.param("item_id"));

    if (!item) {
      return c.json(NOT_FOUND_RESPONSE, 404);
    }

    const now = new Date().toISOString();
    await c.env.DB.batch([
      c.env.DB.prepare(DELETE_COLLECTION_ITEM_SQL).bind(
        auth.owner.owner_type,
        auth.owner.owner_id,
        item.id,
      ),
      collectionItemEventStatement(c.env.DB, auth.owner, item, "delete", now),
    ]);

    return c.json({ success: true, data: {} });
  });

  routes.get("/portfolio/folders", async (c) => {
    const auth = await authenticateOwner(
      c.env,
      c.req.header("Authorization"),
    );

    if (auth.status === "internal_error") {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    if (auth.status === "unauthorized") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const folders = await listFolders(c.env.DB, auth.owner);

    return c.json({
      success: true,
      data: { items: folders.map(folderResponse) },
    });
  });

  routes.post("/portfolio/folders", async (c) => {
    const auth = await authenticateOwner(
      c.env,
      c.req.header("Authorization"),
    );

    if (auth.status === "internal_error") {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    if (auth.status === "unauthorized") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const name = folderNameFromBody(await readJson(c.req));

    if (!name) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    const existingFolders = await listFolders(c.env.DB, auth.owner);
    const sortOrder =
      Math.max(0, ...existingFolders.map((folder) => folder.sort_order)) + 100;
    const now = new Date().toISOString();
    const folderId = createId();

    try {
      await c.env.DB.prepare(INSERT_FOLDER_SQL)
        .bind(
          folderId,
          auth.owner.owner_type,
          auth.owner.owner_id,
          name,
          sortOrder,
          now,
          now,
        )
        .run();
    } catch (error) {
      if (isUniqueConstraintError(error)) {
        return c.json(CONFLICT_RESPONSE, 409);
      }

      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    const folder = await findFolder(c.env.DB, auth.owner, folderId);

    return c.json({ success: true, data: folderResponse(folder!) }, 201);
  });

  routes.patch("/portfolio/folders/reorder", async (c) => {
    const auth = await authenticateOwner(
      c.env,
      c.req.header("Authorization"),
    );

    if (auth.status === "internal_error") {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    if (auth.status === "unauthorized") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const orders = folderOrdersFromBody(await readJson(c.req));

    if (!orders) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    for (const order of orders) {
      const folder = await findFolder(c.env.DB, auth.owner, order.folder_id);

      if (!folder) {
        return c.json(NOT_FOUND_RESPONSE, 404);
      }
    }

    const now = new Date().toISOString();

    await c.env.DB.batch(
      orders.map((order) =>
        c.env.DB.prepare(UPDATE_FOLDER_SORT_ORDER_SQL).bind(
          order.sort_order,
          now,
          auth.owner.owner_type,
          auth.owner.owner_id,
          order.folder_id,
        ),
      ),
    );

    return c.json({ success: true, data: {} });
  });

  routes.patch("/portfolio/folders/:folder_id/set-default", async (c) => {
    const auth = await authenticateOwner(
      c.env,
      c.req.header("Authorization"),
    );

    if (auth.status === "internal_error") {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    if (auth.status === "unauthorized") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const folderId = c.req.param("folder_id");
    const folder = await findFolder(c.env.DB, auth.owner, folderId);

    if (!folder) {
      return c.json(NOT_FOUND_RESPONSE, 404);
    }

    const now = new Date().toISOString();

    await c.env.DB.batch([
      c.env.DB.prepare(CLEAR_DEFAULT_FOLDERS_SQL).bind(
        now,
        auth.owner.owner_type,
        auth.owner.owner_id,
      ),
      c.env.DB.prepare(SET_DEFAULT_FOLDER_SQL).bind(
        now,
        auth.owner.owner_type,
        auth.owner.owner_id,
        folderId,
      ),
    ]);

    const updatedFolder = await findFolder(c.env.DB, auth.owner, folderId);

    return c.json({ success: true, data: folderResponse(updatedFolder!) });
  });

  routes.patch("/portfolio/folders/:folder_id", async (c) => {
    const auth = await authenticateOwner(
      c.env,
      c.req.header("Authorization"),
    );

    if (auth.status === "internal_error") {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    if (auth.status === "unauthorized") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const folderId = c.req.param("folder_id");
    const name = folderNameFromBody(await readJson(c.req));

    if (!name) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    const folder = await findFolder(c.env.DB, auth.owner, folderId);

    if (!folder) {
      return c.json(NOT_FOUND_RESPONSE, 404);
    }

    try {
      await c.env.DB.prepare(UPDATE_FOLDER_NAME_SQL)
        .bind(
          name,
          new Date().toISOString(),
          auth.owner.owner_type,
          auth.owner.owner_id,
          folderId,
        )
        .run();
    } catch (error) {
      if (isUniqueConstraintError(error)) {
        return c.json(CONFLICT_RESPONSE, 409);
      }

      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    const updatedFolder = await findFolder(c.env.DB, auth.owner, folderId);

    return c.json({ success: true, data: folderResponse(updatedFolder!) });
  });

  routes.delete("/portfolio/folders/:folder_id", async (c) => {
    const auth = await authenticateOwner(
      c.env,
      c.req.header("Authorization"),
    );

    if (auth.status === "internal_error") {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    if (auth.status === "unauthorized") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const folderId = c.req.param("folder_id");
    const folder = await findFolder(c.env.DB, auth.owner, folderId);

    if (!folder) {
      return c.json(NOT_FOUND_RESPONSE, 404);
    }

    if (folder.is_default === 1) {
      return c.json(FORBIDDEN_RESPONSE, 403);
    }

    try {
      await c.env.DB.batch([
        c.env.DB.prepare(DELETE_FOLDER_SQL).bind(
          auth.owner.owner_type,
          auth.owner.owner_id,
          folderId,
        ),
        c.env.DB.prepare(CLEAR_LAST_SELECTED_FOLDER_SQL).bind(
          auth.owner.owner_type,
          auth.owner.owner_id,
          folderId,
        ),
      ]);
    } catch {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    return c.json({ success: true, data: {} });
  });

  return routes;
}

async function listFolders(
  db: D1Database,
  owner: AuthenticatedOwner,
): Promise<PortfolioFolderRow[]> {
  const result = await db
    .prepare(SELECT_FOLDERS_SQL)
    .bind(owner.owner_type, owner.owner_id)
    .all<PortfolioFolderRow>();

  return result.results ?? [];
}

async function findFolder(
  db: D1Database,
  owner: AuthenticatedOwner,
  folderId: string,
): Promise<PortfolioFolderRow | null> {
  return db
    .prepare(SELECT_FOLDER_SQL)
    .bind(owner.owner_type, owner.owner_id, folderId)
    .first<PortfolioFolderRow>();
}

async function findDefaultFolder(
  db: D1Database,
  owner: AuthenticatedOwner,
): Promise<PortfolioFolderRow | null> {
  return db
    .prepare(SELECT_DEFAULT_FOLDER_SQL)
    .bind(owner.owner_type, owner.owner_id)
    .first<PortfolioFolderRow>();
}

function folderResponse(folder: PortfolioFolderRow): {
  id: string;
  name: string;
  is_default: boolean;
  sort_order: number;
  created_at: string;
  updated_at: string;
} {
  return {
    id: folder.id,
    name: folder.name,
    is_default: folder.is_default === 1,
    sort_order: folder.sort_order,
    created_at: folder.created_at,
    updated_at: folder.updated_at,
  };
}

async function listCollectionItems(
  db: D1Database,
  owner: AuthenticatedOwner,
): Promise<CollectionItemRow[]> {
  const result = await db
    .prepare(SELECT_COLLECTION_ITEMS_SQL)
    .bind(owner.owner_type, owner.owner_id)
    .all<CollectionItemRow>();

  return result.results ?? [];
}

async function findCollectionItem(
  db: D1Database,
  owner: AuthenticatedOwner,
  itemId: string,
): Promise<CollectionItemRow | null> {
  return db
    .prepare(SELECT_COLLECTION_ITEM_SQL)
    .bind(owner.owner_type, owner.owner_id, itemId)
    .first<CollectionItemRow>();
}

async function findCollectionItemByCard(
  db: D1Database,
  owner: AuthenticatedOwner,
  cardRef: string,
): Promise<CollectionItemRow | null> {
  return db
    .prepare(SELECT_COLLECTION_ITEM_BY_CARD_SQL)
    .bind(owner.owner_type, owner.owner_id, cardRef)
    .first<CollectionItemRow>();
}

function collectionItemResponse(item: CollectionItemRow): Omit<
  CollectionItemRow,
  "owner_type" | "owner_id"
> {
  return {
    id: item.id,
    folder_id: item.folder_id,
    card_ref: item.card_ref,
    object_type: item.object_type,
    grader: item.grader,
    condition: item.condition,
    grade: item.grade,
    language: item.language,
    finish: item.finish,
    quantity: item.quantity,
    purchase_price: item.purchase_price,
    purchase_currency: item.purchase_currency,
    notes: item.notes,
    created_at: item.created_at,
    updated_at: item.updated_at,
  };
}

async function listWishlistItems(
  db: D1Database,
  owner: AuthenticatedOwner,
): Promise<WishlistItemRow[]> {
  const result = await db
    .prepare(SELECT_WISHLIST_ITEMS_SQL)
    .bind(owner.owner_type, owner.owner_id)
    .all<WishlistItemRow>();

  return result.results ?? [];
}

async function findWishlistItem(
  db: D1Database,
  owner: AuthenticatedOwner,
  itemId: string,
): Promise<WishlistItemRow | null> {
  return db
    .prepare(SELECT_WISHLIST_ITEM_SQL)
    .bind(owner.owner_type, owner.owner_id, itemId)
    .first<WishlistItemRow>();
}

function wishlistItemResponse(item: WishlistItemRow): WishlistItemRow {
  return {
    id: item.id,
    card_ref: item.card_ref,
    created_at: item.created_at,
  };
}

async function findUserPreference(
  db: D1Database,
  owner: AuthenticatedOwner,
): Promise<UserPreferenceRow | null> {
  return db
    .prepare(SELECT_USER_PREFERENCE_SQL)
    .bind(owner.owner_type, owner.owner_id)
    .first<UserPreferenceRow>();
}

function userPreferenceResponse(preference: UserPreferenceRow): {
  currency: string;
  amount_hidden: boolean;
  last_selected_folder_id: string | null;
} {
  return {
    currency: preference.currency,
    amount_hidden: preference.amount_hidden === 1,
    last_selected_folder_id: preference.last_selected_folder_id,
  };
}

function collectItemDraftFromBody(
  body: Record<string, unknown>,
  cardRef: string,
  folderId: string,
): CollectionItemDraft | null {
  return collectionItemDraftFromBody(body, {
    folder_id: folderId,
    card_ref: cardRef,
  });
}

function collectionItemEventStatement(
  db: D1Database,
  owner: AuthenticatedOwner,
  item: CollectionItemRow,
  eventType: "upsert" | "delete",
  effectiveAt: string,
): D1PreparedStatement {
  return db.prepare(INSERT_COLLECTION_ITEM_EVENT_SQL).bind(
    createId(),
    item.id,
    owner.owner_type,
    owner.owner_id,
    item.folder_id,
    item.card_ref,
    item.object_type,
    item.grader,
    item.condition,
    item.grade,
    item.language,
    item.finish,
    item.quantity,
    eventType,
    effectiveAt,
  );
}

function sortCollectionItems(
  items: CollectionItemRow[],
  sortBy: keyof Pick<CollectionItemRow, "created_at" | "updated_at" | "card_ref">,
  sortOrder: "asc" | "desc",
): CollectionItemRow[] {
  return [...items].sort((left, right) => {
    const direction = sortOrder === "asc" ? 1 : -1;

    return String(left[sortBy]).localeCompare(String(right[sortBy])) * direction;
  });
}

function itemSortBy(
  value: string | undefined,
): keyof Pick<CollectionItemRow, "created_at" | "updated_at" | "card_ref"> {
  return ITEM_SORT_FIELDS.has(value ?? "")
    ? (value as "created_at" | "updated_at" | "card_ref")
    : "created_at";
}

function sortWishlistItems(
  items: WishlistItemRow[],
  sortBy: keyof Pick<WishlistItemRow, "created_at" | "card_ref">,
  sortOrder: "asc" | "desc",
): WishlistItemRow[] {
  return [...items].sort((left, right) => {
    const direction = sortOrder === "asc" ? 1 : -1;

    return String(left[sortBy]).localeCompare(String(right[sortBy])) * direction;
  });
}

function wishlistSortBy(
  value: string | undefined,
): keyof Pick<WishlistItemRow, "created_at" | "card_ref"> {
  return WISHLIST_SORT_FIELDS.has(value ?? "")
    ? (value as "created_at" | "card_ref")
    : "created_at";
}

async function readJson(request: { json(): Promise<unknown> }): Promise<unknown> {
  try {
    return await request.json();
  } catch {
    return null;
  }
}

function folderNameFromBody(body: unknown): string | null {
  if (!isRecord(body) || typeof body.name !== "string") {
    return null;
  }

  const name = body.name.trim();

  return name.length > 0 && name.length <= 50 ? name : null;
}

function folderOrdersFromBody(body: unknown): FolderOrder[] | null {
  if (!isRecord(body) || !Array.isArray(body.orders)) {
    return null;
  }

  const orders: FolderOrder[] = [];

  for (const order of body.orders) {
    if (
      !isRecord(order) ||
      typeof order.folder_id !== "string" ||
      order.folder_id.trim().length === 0 ||
      typeof order.sort_order !== "number" ||
      !Number.isSafeInteger(order.sort_order) ||
      order.sort_order < 0
    ) {
      return null;
    }

    orders.push({
      folder_id: order.folder_id.trim(),
      sort_order: order.sort_order,
    });
  }

  return orders;
}

function wishlistCardRefFromBody(body: unknown): string | null {
  if (!isRecord(body)) {
    return null;
  }

  return requiredString(body.card_ref);
}

function collectFolderIdFromBody(
  body: Record<string, unknown>,
): string | null | undefined {
  if (body.folder_id === undefined || body.folder_id === null) {
    return null;
  }

  return requiredString(body.folder_id) ?? undefined;
}

function userPreferencePatchFromBody(
  body: unknown,
  preference: UserPreferenceRow,
): UserPreferencePatch | null {
  if (!isRecord(body)) {
    return null;
  }

  let currency = preference.currency;
  let amountHidden = preference.amount_hidden;
  let lastSelectedFolderId = preference.last_selected_folder_id;
  let folderIdToValidate: string | null = null;

  if (body.currency !== undefined) {
    const parsedCurrency = requiredString(body.currency);

    if (!parsedCurrency || !ISO_4217_CURRENCY_PATTERN.test(parsedCurrency)) {
      return null;
    }

    currency = parsedCurrency;
  }

  if (body.amount_hidden !== undefined) {
    if (typeof body.amount_hidden !== "boolean") {
      return null;
    }

    amountHidden = body.amount_hidden ? 1 : 0;
  }

  if (body.last_selected_folder_id !== undefined) {
    if (body.last_selected_folder_id === null) {
      lastSelectedFolderId = null;
    } else {
      const folderId = requiredString(body.last_selected_folder_id);

      if (!folderId) {
        return null;
      }

      lastSelectedFolderId = folderId;
      folderIdToValidate = folderId;
    }
  }

  return {
    currency,
    amount_hidden: amountHidden,
    last_selected_folder_id: lastSelectedFolderId,
    folder_id_to_validate: folderIdToValidate,
  };
}

function requiredString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

function nullableString(value: string | undefined): string | null {
  return requiredString(value);
}

function positiveIntegerOrDefault(
  value: string | undefined,
  fallback: number,
  max?: number,
): number {
  if (!value || !/^\d+$/.test(value)) {
    return fallback;
  }

  const parsed = Number(value);

  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    return fallback;
  }

  return max ? Math.min(parsed, max) : parsed;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isUniqueConstraintError(error: unknown): boolean {
  return (
    error instanceof Error &&
    error.message.toLowerCase().includes("unique constraint")
  );
}
