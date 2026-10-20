// Adapter D1 minimal di atas node:sqlite — cukup untuk menjalankan
// Cloudflare Pages Functions tunnel (prepare/bind/all/run/first/batch)
// di test lokal & CI tanpa wrangler/miniflare.
import { DatabaseSync } from "node:sqlite";

class FakeStatement {
  constructor(db, sql) {
    this.db = db;
    this.sql = sql;
    this.params = [];
  }
  bind(...params) {
    this.params = params;
    return this;
  }
  async all() {
    const rows = this.db.prepare(this.sql).all(...this.params);
    return { results: rows, success: true };
  }
  async run() {
    const info = this.db.prepare(this.sql).run(...this.params);
    return { success: true, meta: { changes: Number(info.changes) } };
  }
  async first() {
    const row = this.db.prepare(this.sql).get(...this.params);
    return row ?? null;
  }
}

export class FakeD1 {
  constructor(schemaSql) {
    this.db = new DatabaseSync(":memory:");
    if (schemaSql) this.db.exec(schemaSql);
  }
  prepare(sql) {
    return new FakeStatement(this.db, sql);
  }
  async batch(statements) {
    const out = [];
    this.db.exec("BEGIN");
    try {
      for (const s of statements) out.push(await s.run());
      this.db.exec("COMMIT");
    } catch (e) {
      this.db.exec("ROLLBACK");
      throw e;
    }
    return out;
  }
  // Akses mentah untuk setup/assert di test.
  raw(sql, ...params) {
    return this.db.prepare(sql).all(...params);
  }
  rawRun(sql, ...params) {
    return this.db.prepare(sql).run(...params);
  }
}
