---
title: lucid-tenancy — API pública de saúde e migração por tenant
status: proposed
created: 2026-11-20
updated: 2026-11-21
owner: "@oporpino"
certainty: high
---

# lucid-tenancy — API pública de saúde e migração por tenant

> **TLDR**: expor em `lucid-tenancy` `Lucid::Tenancy.health(tenant)` (divergência do schema do tenant em relação ao template: existência, tabelas, colunas, versões pendentes) e `Lucid::Tenancy.migrate(tenant)` (aplica só as migrations `tenancy :tenant` pendentes desse tenant), para o `lucid-backoffice` mostrar a saúde do schema e oferecer a correção sem conhecer internals da gem.

Spec 1 da sequência backoffice (ADR `docs/adr/0007-backoffice-as-standalone-gem-with-adapters.md`). Repo: `br4zz4/lucid-tenancy` (`~/workspace/br4zz4/lucid-tenancy`). Esta spec é copiada para `docs/specs/` do repo da gem no primeiro PR.

# what

Como dev de um app com `lucid-tenancy`, quero perguntar à gem se o schema de um tenant está igual ao template e aplicar só as migrations pendentes desse tenant, para diagnosticar e corrigir drift por tenant sem rodar `db:migrate` em todos nem ler `information_schema` na mão.

## out of scope

- Corrigir drift que não vem de migration (coluna alterada à mão, tabela extra): só reportar.
- Rollback por tenant.
- Comparar índices, constraints e defaults (só tabelas, colunas e tipos).
- Qualquer UI (é do backoffice).

## acceptance criteria

    Cenário: tenant em dia
      Dado o tenant "alfa" provisionado do template sem divergência
      Quando chamo Lucid::Tenancy.health(alfa)
      Então provisioned? é true, ok? é true e todas as listas vêm vazias

    Cenário: divergências
      Dado que "alfa" não tem a tabela "notes", tem a tabela extra "tmp_x", a coluna "children.cpf" é integer no tenant e string no template, falta "children.sex" e falta a versão 20261101000000
      Quando chamo health(alfa)
      Então missing_tables = ["notes"], extra_tables = ["tmp_x"]
      E column_drift lista {table: "children", column: "cpf", expected: "character varying", actual: "integer"} e {table: "children", column: "sex", expected: "character varying", actual: nil}
      E pending_versions = [20261101000000] e ok? é false

    Cenário: schema inexistente
      Dado um tenant cujo schema não existe
      Quando chamo health
      Então provisioned? é false, ok? é false e nenhuma query de colunas é feita

    Cenário: health não lê linhas nem escreve
      Quando health roda
      Então só consulta catálogo (information_schema, pg_namespace, schema_migrations) e não emite INSERT/UPDATE/DELETE/DDL

    Cenário: migrar um tenant
      Dado "alfa" com 2 migrations tenancy :tenant pendentes e "beta" com as mesmas pendentes
      Quando chamo Lucid::Tenancy.migrate(alfa)
      Então as 2 rodam só em "alfa", ficam registradas em alfa.schema_migrations, e "beta" e o template não mudam
      E migrations tenancy :shared não rodam

    Cenário alternativo: migrar tenant não provisionado
      Quando chamo migrate num tenant sem schema
      Então levanta Lucid::Tenancy::Error::NotProvisioned e nada é criado

    Cenário: pending por tenant
      Quando chamo Lucid::Tenancy.pending(tenant: alfa)
      Então recebo só as versões pendentes de "alfa" (Array<Integer>), sem iterar os outros tenants

# why

O backoffice (`lucid-backoffice`) mostra a saúde do schema de cada tenant e oferece a ação "aplicar migrations pendentes". Esse conhecimento (template, `schema_migrations` por schema, quais migrations são de tenant) é da `lucid-tenancy`; reimplementá-lo no backoffice duplicaria regra e quebraria a cada mudança interna. `Migrator.pending` já existe, mas percorre todos os schemas e não há migração por tenant.

# how

Regras: TDD, testes minitest contra PostgreSQL real como o resto da gem, sem comentários explicativos, YARD nos métodos públicos, docs em inglês.

**Feature flag:** não. API aditiva.

**Telas:** sem telas.

**Staging:** `staging: none`.

## Desenho

- `Lucid::Tenancy::Health` (`Data.define(:schema, :provisioned, :missing_tables, :extra_tables, :column_drift, :pending_versions)`, `provisioned?`, `ok?`). `ColumnDrift = Data.define(:table, :column, :expected, :actual)`.
- `Lucid::Tenancy.health(tenant)`: compara `information_schema.columns` (`table_name`, `column_name`, `data_type`) do schema do tenant com o do `Template.schema`, ignorando `schema_migrations` e `ar_internal_metadata`; `pending_versions` = `pending(tenant:)`.
- `Lucid::Tenancy.pending(tenant: nil, paths:)`: com `tenant`, devolve `Array<Integer>` só daquele schema; sem, comportamento atual (Hash por schema).
- `Lucid::Tenancy.migrate(tenant, paths: default)`: `Schema.with_path(tenant.schema_name)` + contexto `:tenant` do `Migrator`, só migrations `tenancy :tenant`; `Error::NotProvisioned` se o schema não existe.

## PR 1 — health e pending por tenant (branch: `feat/tenant-health-1`, base: `main`)
**Arquivos:** Create `lib/lucid/tenancy/health.rb` — Modify `lib/lucid/tenancy.rb`, `lib/lucid/tenancy/migrator.rb`, `lib/lucid/tenancy/errors.rb` (`NotProvisioned < Error`, ainda não existe) — Test `test/lucid/tenancy/health_test.rb` (novo), `test/lucid/tenancy/pending_api_test.rb` (existente: casos de `pending(tenant:)`) — Docs: `docs/specs/20261120210000_lucid_tenancy_health_api.md` (cópia)
**Passos:** testes dos 4 primeiros cenários + pending por tenant → implementação → commit `feat: add tenant health and per-tenant pending`
**Pronto para prod:** só adiciona API.
**Valida:** `bundle exec rake test`

## PR 2 — migrate por tenant, docs e release (branch: `feat/tenant-health-2`, base: `feat/tenant-health-1`)
**Arquivos:** Modify `lib/lucid/tenancy.rb`, `lib/lucid/tenancy/migrator.rb`, `lib/lucid/tenancy/version.rb` (0.3.0 → 0.4.0), `CHANGELOG.md` (seção `## 0.4.0` no formato das anteriores, com "Upgrading from 0.3.0"), `docs/migrations.md` (seção "Per-tenant health and migrate") — Test `test/lucid/tenancy/migrate_tenant_test.rb`
**Passos:** testes de migrar um tenant e não provisionado → implementação → tag `v0.4.0` → commit `feat: migrate a single tenant`
**Pronto para prod:** aditivo.
**Valida:** `bundle exec rake test`

## SEQUENCE
1. #<pr1> — health e pending por tenant
2. #<pr2> — migrate por tenant e release
Merge in this order: #<pr1> #<pr2>

# definition of done

- [ ] Todo cenário de "acceptance criteria" foi validado (automatizado ou verificado com comando exato)
- [ ] Testes automáticos passando — suíte verde, não só a parte nova (`bundle exec rake test`, CI ubuntu e macOS)
- [ ] Toda task do "how" executada
- [ ] Documentação atualizada (`docs/migrations.md`, `CHANGELOG.md`)
- [ ] Staging: `staging: none` (gem)
- [ ] Cada PR da sequência validado isoladamente (build e testes verdes sem os PRs seguintes)
- [ ] Último PR liga a funcionalidade e remove código temporário (tag `v0.4.0` publicada)
- [ ] health em dia, com divergências, sem schema e sem escrita (`test/lucid/tenancy/health_test.rb`)
- [ ] migrate só no tenant e erro sem schema (`test/lucid/tenancy/migrate_tenant_test.rb`)
- [ ] pending(tenant:) só daquele tenant, sem mudar o retorno de `pending` sem argumento (`test/lucid/tenancy/pending_api_test.rb`)

## documentation

- `docs/migrations.md` da gem: `health`, `pending(tenant:)`, `migrate(tenant)`.
- `CHANGELOG.md` da gem.
