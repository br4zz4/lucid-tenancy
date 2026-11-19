---
title: Gem lucid-tenancy — um schema PostgreSQL por tenant, extraída do lib/hotel do luneta
status: proposed
created: 2026-11-19
updated: 2026-11-19
owner: "@oporpino"
certainty: high
---

# Gem lucid-tenancy — um schema PostgreSQL por tenant

> **TLDR**: extrair a tenancy do luneta (`lib/hotel*.rb`, `TenantMiddleware`, `TenantMigrationContext`, tasks de tenant) para a gem genérica `lucid-tenancy` (`br4zz4/lucid-tenancy`, `Lucid::Tenancy`), corrigindo os defeitos encontrados (jobs no schema errado, migrations que não chegam aos tenants existentes, rake destrutivo, schema sem aspas), e adotá-la no luneta trocando todos os call sites.

Spec 2 de 3 da família `Lucid` (`lucid-case` feita → `lucid-tenancy` → `lucid-backoffice`). Decisão e nomes: `docs/adr/0006-tenancy-gem-schema-per-tenant-on-postgres.md`. Mapeamento do código atual: relatório de 2026-11-19 (resumido em "why").

# what

Como dev Brazza, quero uma gem de multi-tenancy genérica para qualquer app Rails sobre PostgreSQL, que isole cada tenant em um schema próprio e cuide de requisição, job, console, migrations e criação de tenants do mesmo jeito, para parar de reescrever (e de errar) esse encanamento em cada projeto e corrigir os defeitos do luneta.

## out of scope

- Outros bancos além de PostgreSQL e outras estratégias de isolamento (coluna `tenant_id`, banco por tenant). É regra da gem, não opção.
- O painel de operação (`lucid-backoffice`) e suas telas.
- Regras de domínio do luneta: `Organization` (campos, CNPJ, representante), `RESERVED_SUBDOMAINS` do domínio, `/landing`, `/404`, `www`, heurística `.com.br`, `SubdomainProvisioning` (Cloudflare), seed `escolamagica`. Ficam no app, ligados por configuração.
- Dump em SQL (`structure.sql`) para triggers, funções e views: o luneta não usa nenhum; fica no roadmap da gem.
- Publicar no RubyGems (consumo por `github:` + `tag:`).
- Sub-domínio editável após a criação (renomear schema): segue proibido, agora com validação.
- Corrigir fora da tenancy os bugs da `main` achados na migração do u-case (índice único de `class_enrollments`, job inexistente em `subscribers.rb`, `GoToState#retreat_to`).

## acceptance criteria

### Gem

    Cenário: trocar de tenant com bloco
      Dado dois tenants "alfa" e "beta" com um aluno em "alfa" e nenhum em "beta"
      Quando executo `Lucid::Tenancy.with(tenant: alfa) { Student.count }` e depois o mesmo com "beta"
      Então recebo 1 e 0, e `search_path` volta ao valor anterior ao fim de cada bloco

    Cenário: o bloco restaura o schema mesmo com exceção
      Quando o bloco de `with(tenant: alfa)` levanta uma exceção
      Então a exceção sobe para quem chamou e o schema volta ao anterior

    Cenário: trocar sem bloco
      Quando chamo `Lucid::Tenancy.set(tenant: alfa)`
      Então `Lucid::Tenancy.current` é "alfa" e as queries usam o schema "alfa"
      E `Lucid::Tenancy.set(tenant: nil)` volta ao shared e `current` é nil
      E `set(tenant: alfa) { }` com bloco se comporta como `with`

    Cenário: shared
      Quando executo `Lucid::Tenancy.shared { ... }` ou `with(tenant: nil) { ... }`
      Então as queries usam só o schema público e tabelas `tenancy :tenant` não são encontradas

    Cenário: tabelas compartilhadas
      Dado `class Organization; tenancy :shared; end`
      Quando consulto `Organization.count` dentro de `with(tenant: alfa)`
      Então a consulta usa `public.organizations`

    Cenário: Enumerable
      Dado três tenants
      Quando executo `Lucid::Tenancy.each { |t| Student.count }`, `map` e `find`
      Então cada bloco roda no schema do seu tenant e o schema anterior é restaurado ao fim
      E `Lucid::Tenancy.count` e `to_a` não trocam de schema
      E `find` que para no meio restaura o schema

    Cenário: configuração por initializer e por concern
      Dado `config.tenant_model = "Organization"` e `config.tenant_identifier = :subdomain`
      Então o model recebe `Lucid::Tenancy::Tenant` sozinho (`schema_name`, validação do identificador, `provision`, `drop`)
      E declarar `include Lucid::Tenancy::Tenant` com `tenant_identifier :subdomain` no model também funciona
      E declarar nos dois lugares com valores diferentes, ou dois models como tenant, levanta erro no boot

    Cenário: identificador vira nome de schema com segurança
      Dado o identificador "escola-alfa"
      Então o schema é "escola_alfa", e todo SQL gerado cita o identificador (`quote_table_name`)
      E identificadores fora de `[a-z][a-z0-9_]{1,62}` após a normalização são inválidos
      E "public", o schema template, qualquer "pg_*" e "information_schema" são recusados

    Cenário: provisionar um tenant
      Dado o dump do schema template em `db/tenant_schema.rb`
      Quando executo `Lucid::Tenancy.provision(tenant)`
      Então o schema existe com todas as tabelas, índices, chaves estrangeiras e sequências próprias
      E `schema_migrations` do novo schema tem as versões do dump
      E provisionar de novo um tenant que já tem schema levanta erro, sem alterar nada

    Cenário alternativo: falha no meio da provisão
      Quando o carregamento do dump falha na 20ª tabela
      Então nenhum schema do tenant fica no banco (transação revertida)

    Cenário: migration de tenant roda de verdade em cada tenant
      Dado tenants "alfa" e "beta" já provisionados e uma migration nova `tenancy :tenant` que adiciona uma coluna
      Quando rodo `bin/rails db:migrate`
      Então a coluna existe em "alfa", "beta" e no template, e cada `schema_migrations` registra a versão
      E rodar de novo não repete nada

    Cenário: migration shared roda só no schema público
      Dado uma migration `tenancy :shared`
      Quando rodo `db:migrate`
      Então ela roda uma vez no público e não roda nos tenants

    Cenário alternativo: migration sem declaração
      Quando uma migration não declara `tenancy`
      Então `db:migrate` falha com a mensagem apontando o arquivo, sem ler o texto da migration para adivinhar

    Cenário: rollback
      Quando rodo `db:rollback` ou `db:rollback:all`
      Então desfaz a última migration (ou todas) em cada tenant e no template, sem aborto silencioso

    Cenário alternativo: migrate nunca apaga tenants
      Dado um tenant com poucas tabelas
      Quando rodo `db:migrate`
      Então o schema do tenant não é apagado nem recriado

    Cenário: dump do template
      Quando rodo `db:schema:dump`
      Então `db/tenant_schema.rb` reflete o template, e o CI da gem falha se o dump está fora de sincronia com as migrations

    Cenário: requisição resolve o tenant e limpa no fim
      Dado `config.base_domain = "app.test"` e um tenant "alfa"
      Quando chega uma requisição em `alfa.app.test`
      Então o código da requisição roda no schema "alfa" e, ao fim da resposta (inclusive corpo em streaming), o schema volta ao shared
      E duas requisições seguidas na mesma conexão não vazam o schema

    Cenário: tenant inexistente
      Quando chega uma requisição em um subdomínio sem tenant
      Então o `on_missing_tenant` configurado responde (padrão 404), sem reescrever `PATH_INFO`

    Cenário: caminhos compartilhados com fronteira
      Dado `shared_paths = ["/up", "/admin"]`
      Então `/up`, `/up/x` e `/admin/users` rodam no shared e `/update`, `/upload`, `/administracao` seguem a resolução normal

    Cenário alternativo: X-Forwarded-Host
      Quando a requisição traz `X-Forwarded-Host` de um proxy fora de `trusted_proxies`
      Então o header é ignorado

    Cenário: Active Job leva o tenant
      Dado um job enfileirado dentro de `with(tenant: alfa)`
      Quando o worker executa o job
      Então ele roda no schema "alfa" e restaura o schema depois
      E um job com `tenancy :shared` roda no público, e um job enfileirado fora de tenant roda no público

    Cenário: Action Cable e testes
      Então a gem oferece `Lucid::Tenancy::ActionCable` para identificar o tenant na conexão e helpers para RSpec e Minitest que trocam de tenant por teste

    Cenário: plataforma
      Quando o CI da gem roda
      Então a suíte passa em ubuntu Ruby 3.2, ubuntu Ruby 3.4 e macOS Ruby 3.4, com PostgreSQL

### Luneta

    Cenário: nada de Hotel no código
      Dado o último PR mergeado
      Então `grep -rn "Hotel\b\|HotelTenancy\|TenantMiddleware\|TenantMigrationContext\|Tenant\.with\|Current.organization" modules/core/code/app modules/core/code/lib modules/core/code/config modules/core/code/spec` não retorna nada

    Cenário: jobs de tenant rodam na escola certa
      Dado `AttendanceNotificationJob` e `PedagogicalStatusAlertJob` enfileirados para a escola "alfa"
      Quando o worker os executa
      Então eles leem e gravam dados do schema "alfa" e a conexão volta ao shared

    Cenário: migration nova chega às escolas existentes
      Dado as escolas "alfa" e "beta" e uma migration nova que adiciona uma coluna a `students`
      Quando o job de migração do deploy roda
      Então a coluna existe em todas as escolas

    Cenário: criar escola
      Quando `Organization::Create` cria a escola "gama"
      Então `Lucid::Tenancy.provision` cria o schema "gama" completo (chaves estrangeiras e sequências próprias) e o provisionamento de subdomínio é enfileirado depois do commit

    Cenário alternativo: subdomínio perigoso
      Quando alguém tenta criar uma escola com subdomínio "public", "staff", "pg_catalog" ou "a b"
      Então a criação falha na validação

    Cenário: requisições e rotas do luneta
      Então escolas respondem em `<sub>.<domínio>`, `/up`, `/p/...`, `/tasks/...` e `/sysadmin` funcionam como hoje, `www` e raiz vão para `/landing` e subdomínio inexistente responde 404, e a suíte inteira continua verde

# why

A tenancy do luneta funciona, mas o mapeamento do código mostrou defeitos reais que a extração precisa corrigir em vez de copiar:

- **Jobs no schema errado.** `AttendanceNotificationJob` e `PedagogicalStatusAlertJob` chamam `Hotel.checkin(...) do ... end`, mas `checkin` não aceita bloco e o descarta: o trabalho roda em `public` e a conexão fica presa no último tenant. O tenant também não é propagado ao enfileirar.
- **Migrations não chegam aos tenants existentes.** Para tenants antigos o código copia a versão da migration para `schema_migrations` sem rodar o SQL; só tabelas novas chegam corretas.
- **Rake destrutivo e quebrado.** `db:migrate:tenants` apaga e recria schemas com 1 a 4 tabelas; `db:rollback:all` sempre aborta por um nome de método errado escondido por `rescue`.
- **Segurança.** O subdomínio vira nome de schema sem aspas e sem reservar `staff`, `public`, `pg_*`. Os prefixos de rota não têm fronteira (`/up` casa `/update`). `X-Forwarded-Host` é aceito sem lista de proxies.
- **Clone incompleto.** `CREATE TABLE ... LIKE ... INCLUDING ALL` não copia chaves estrangeiras nem triggers, e defaults de sequência podem apontar para o schema modelo.
- **Decisão de migration frágil.** Um `include?('in_staff')` sobre o texto do arquivo decide em que schema a migration roda, inclusive olhando comentários.

Uma gem genérica corrige isso uma vez, dá a mesma garantia em requisição, job, console e rake, e é a base do `lucid-backoffice` (navegação por tenant).

# how

Regras: TDD (o tester escreve o teste que falha a partir do Gherkin; o builder implementa), Minitest na gem com PostgreSQL real (`test/dummy` com banco), RSpec Triple-A sem `let` no luneta. Sem comentários explicativos; API pública com YARD; documentação em inglês, em guias pequenos e diretos (estilo do `lucid-case`). Variáveis de ambiente nomeiam o quê (`DATABASE_URL`).

**Feature flag:** não. Na gem tudo é novo. No luneta a troca é interna e mantém o comportamento observável; o único comportamento novo (jobs e migrations corretos) é correção.

**Telas criadas/editadas:** sem telas.

**Staging:** `staging: none`.

## Desenho da gem

Repo `~/workspace/br4zz4/lucid-tenancy` → `github.com/br4zz4/lucid-tenancy`. Gem `lucid-tenancy`, `require "lucid/tenancy"`, módulo `Lucid::Tenancy` (nada solto em `Lucid`). Ruby `>= 3.2`; `activerecord`, `activesupport`, `railties` `>= 7.2, < 9`; PostgreSQL (`pg` só nos testes). MIT. Versionamento normal: commit novo + bump + tag; não reescrever histórico.

**Estado:** `Lucid::Tenancy::State` por `ActiveSupport::IsolatedExecutionState` (thread e fiber), com o tenant corrente. Ao emprestar uma conexão, o `search_path` é aplicado a partir do estado (callback de checkout) e limpo no checkin, para não vazar pelo pool; blocos usam `ensure`.

**API:**
- `Lucid::Tenancy.with(tenant: x) { }` (`x` é o tenant ou o identificador; `nil` = shared), `shared { }`, `set(tenant: x)` / `set(tenant: nil)` (com bloco = `with`), `current` (o tenant ou `nil`), `current_scope` (`:tenant` ou `:shared`).
- Enumerable: `each`, `map`, `find`... com o bloco dentro do schema de cada tenant; `count`, `size` e `to_a` sem trocar de schema.
- `tenancy :shared | :tenant` em models (`:tenant` padrão) e em migrations. `:shared` força `table_name` para `public.<tabela>`.
- `Lucid::Tenancy::Tenant` (concern do model do tenant): `tenant_identifier :subdomain`, validação do identificador (formato, reservados), `schema_name`, `provision`, `drop`. Config alternativa: `config.tenant_model = "Organization"` (string, resolvida de forma preguiçosa para sobreviver ao reload) e `config.tenant_identifier`; a gem inclui o concern sozinha. Conflito entre as duas formas → erro no boot.
- `Lucid::Tenancy.provision(tenant)` / `drop(tenant)`: criam/removem o schema carregando `db/tenant_schema.rb` dentro de uma transação, com `schema_migrations` semeado a partir do dump; hook `config.after_provision = ->(tenant) { }` para dados iniciais.
- Template: schema interno (`config.template_schema`, padrão `tenancy_template`), migrado junto com os tenants; não faz parte da API pública (`with_template` não existe).
- Erros: `Lucid::Tenancy::Error::{InvalidIdentifier, ReservedIdentifier, TenantNotFound, AlreadyProvisioned, MissingTenancyDeclaration, ConfigurationConflict}`.

**Migrations:** `ActiveRecord::Migration` ganha `tenancy :tenant | :shared`. `db:migrate` (sobrescrito com segurança) roda as `shared` uma vez no público e as `tenant` no template e em cada tenant, registrando a versão no `schema_migrations` de cada schema; `db:rollback`, `db:rollback:all`, `db:migrate:status` equivalentes. Migration sem declaração falha com mensagem clara (sem leitura do texto). Nunca apaga schemas. `db:schema:dump` gera `db/schema.rb` (shared) e `db/tenant_schema.rb` (template); o CI do app confere se o dump está em dia (`rake lucid:tenancy:check`).

**Middleware** (`Lucid::Tenancy::Middleware`, inserido pelo Railtie antes de `ActionDispatch::Cookies`): `config.base_domain`, `config.resolver` (callable `request -> identificador`, padrão por subdomínio), `config.shared_paths` com fronteira de caminho, `config.on_missing_tenant` (callable Rack, padrão 404), `config.trusted_proxies` para `X-Forwarded-Host`. Limpa o schema no fim, inclusive com corpo em streaming (`Rack::BodyProxy`).

**Active Job:** `Lucid::Tenancy::ActiveJobExtension` (incluída em `ActiveJob::Base`): ao serializar guarda o identificador do tenant corrente; ao executar troca e restaura. `tenancy :shared` no job desliga a propagação. Também `Lucid::Tenancy::ActionCable` (`identified_by :tenant`) e `Lucid::Tenancy::RSpec` / `::Minitest` (um tenant por teste).

**Configuração** (`Lucid::Tenancy.configure`, gerada por `rails g lucid:tenancy:install` em `config/initializers/lucid_tenancy.rb`): `tenant_model`, `tenant_identifier`, `template_schema`, `base_domain`, `resolver`, `shared_paths`, `on_missing_tenant`, `trusted_proxies`, `after_provision`, `reserved_identifiers`.

## Documentação da gem

Em inglês, no padrão do `lucid-case` (prosa direta, sem tabelas desnecessárias): `README.md` (primeiro exemplo em destaque: `with(tenant:)` + job), `docs/getting-started.md`, `docs/tenant-model.md` (concern e configuração), `docs/switching.md` (`with`, `shared`, `set`, `current`, Enumerable), `docs/migrations.md` (`tenancy`, rollback, dump, template, CI), `docs/provisioning.md` (dump, transação, hooks, limitações do dump do Rails), `docs/middleware.md`, `docs/jobs.md` (Active Job e Action Cable), `docs/testing.md`, `docs/configuration.md`, `docs/errors.md`, `docs/decisions.md` (PostgreSQL apenas e schema por tenant sempre, com os motivos), `docs/migrating-from-hotel.md` (tabela de equivalências), `docs/roadmap.md`, `CHANGELOG.md`.

## Parte A — repo `br4zz4/lucid-tenancy`

Antes do PR A1: criar `~/workspace/br4zz4/lucid-tenancy` (`git init`, commit inicial na `main` com `LICENSE`, `.gitignore`, `README.md` de uma linha) e o repositório remoto `br4zz4/lucid-tenancy`. **Criar o repo no GitHub é ação externa: o builder confirma com o usuário antes do `gh repo create`.**

### PR A1 — núcleo: estado, troca de tenant e models (branch `feat/lucid-tenancy-1`, base `main`)
**Entrega:** esqueleto, `State`, `with`/`shared`/`set`/`current`, `tenancy :shared|:tenant` em models, identificador (validação, normalização, citação, reservados), configuração, erros, CI com PostgreSQL.
**Arquivos:** Create `lucid-tenancy.gemspec`, `Gemfile`, `Rakefile`, `mise.toml`, `.github/workflows/ci.yml`, `lib/lucid-tenancy.rb`, `lib/lucid/tenancy.rb`, `lib/lucid/tenancy/{version,errors,configuration,state,identifier,model}.rb`, `docs/specs/20261119180000_lucid_tenancy_gem.md` — Test (tester) `test/test_helper.rb` (dummy com PostgreSQL), `test/lucid/tenancy/{switching,identifier,model,configuration}_test.rb`
**Pronto para prod:** gem nova.
**Valida:** `bundle exec rake test`

### PR A2 — tenant model, Enumerable e provisionamento (branch `feat/lucid-tenancy-2`, base `feat/lucid-tenancy-1`)
**Entrega:** concern `Lucid::Tenancy::Tenant` e configuração por `tenant_model`, `each`/`map`/`find`, `provision`/`drop` com dump em transação, hook `after_provision`, conflito de configuração.
**Arquivos:** Create `lib/lucid/tenancy/{tenant,collection,provisioner,template}.rb` — Modify `lib/lucid/tenancy.rb`, `lib/lucid/tenancy/configuration.rb` — Test `test/lucid/tenancy/{tenant,collection,provisioning}_test.rb`
**Valida:** `bundle exec rake test`

### PR A3 — migrations, rollback e dump (branch `feat/lucid-tenancy-3`, base `feat/lucid-tenancy-2`)
**Entrega:** `tenancy` em migrations, `db:migrate`/`rollback`/`status` por schema, template migrado, dump `tenant_schema.rb`, `lucid:tenancy:check`, Railtie com as tasks.
**Arquivos:** Create `lib/lucid/tenancy/{migration,migrator,schema_dump,railtie}.rb`, `lib/tasks/lucid_tenancy.rake` — Test `test/lucid/tenancy/{migration,migrator,schema_dump}_test.rb`
**Valida:** `bundle exec rake test`

### PR A4 — middleware e resolução de host (branch `feat/lucid-tenancy-4`, base `feat/lucid-tenancy-3`)
**Entrega:** `Middleware`, `Resolver`, `shared_paths` com fronteira, `on_missing_tenant`, `trusted_proxies`, limpeza com `BodyProxy`.
**Arquivos:** Create `lib/lucid/tenancy/{middleware,resolver}.rb` — Modify `lib/lucid/tenancy/railtie.rb` — Test `test/lucid/tenancy/{middleware,resolver}_test.rb`
**Valida:** `bundle exec rake test`

### PR A5 — jobs, cable e helpers de teste (branch `feat/lucid-tenancy-5`, base `feat/lucid-tenancy-4`)
**Entrega:** `ActiveJobExtension`, `ActionCable`, helpers `RSpec` e `Minitest`.
**Arquivos:** Create `lib/lucid/tenancy/{active_job_extension,action_cable,rspec,minitest}.rb` — Modify `lib/lucid/tenancy/railtie.rb` — Test `test/lucid/tenancy/{active_job,action_cable,test_helpers}_test.rb`
**Valida:** `bundle exec rake test`

### PR A6 — gerador, documentação e v0.1.0 (branch `feat/lucid-tenancy-6`, base `feat/lucid-tenancy-5`)
**Entrega:** `rails g lucid:tenancy:install`, toda a documentação e YARD, tag `v0.1.0` após o merge.
**Arquivos:** Create `lib/generators/lucid/tenancy/install/{install_generator.rb,templates/lucid_tenancy.rb.tt}`, `README.md`, `CHANGELOG.md`, `docs/*.md` (lista acima) — Test `test/generators/install_generator_test.rb`
**Valida:** `bundle exec rake test && git tag v0.1.0 && git push origin v0.1.0`

## Parte B — luneta (depois da tag `v0.1.0`)

Mapa de call sites a migrar (`Hotel.checkin` 8, `checkout` 3, `as_guest` 8, `as_staff` 3, `at_lobby` 12, `guests` 9, `staff` 2, `current` 2, `Current.organization` 15 leituras, `TenantResolver` 3, `tenant :public` 4 models, `in_staff` em 54 migrations): `Hotel.as_guest(x) { }` → `Lucid::Tenancy.with(tenant: x) { }`; `Hotel.at_lobby { }` → `Lucid::Tenancy.shared { }`; `Hotel.guests.each { |s| as_guest(s) }` → `Lucid::Tenancy.each { }`; `Hotel.checkin(x)`/`checkout` → `set(tenant: x)`/`set(tenant: nil)`; `Hotel.current`/`Current.organization` → `Lucid::Tenancy.current`; `tenant :public` → `tenancy :shared`; `in_staff do ... end` nas migrations → `tenancy :tenant` na classe e o corpo sem o wrapper; `as_staff` no middleware das rotas de admin sai (o backoffice roda no shared).

### PR B1 — gem e configuração (branch `feat/lucid-tenancy-luneta-1`, base `main`)
**Entrega:** gem no Gemfile, initializer com `tenant_model = "Organization"`, `tenant_identifier = :subdomain`, `base_domain` (de `TENANT_BASE_DOMAIN`), `shared_paths` (`/up`, `/p`, `/tasks`, `/sysadmin`), `on_missing_tenant`, `template_schema = "staff"` (mantém o schema atual como template), `after_provision`; ainda sem uso.
**Arquivos:** Modify `modules/core/code/Gemfile`, `Gemfile.lock` — Create `modules/core/code/config/initializers/lucid_tenancy.rb` — Test `spec/initializers/lucid_tenancy_spec.rb`
**Pronto para prod:** gem carregada sem trocar o comportamento (middleware da gem desligado até o B2).
**Valida:** `make core.test spec=spec/initializers/lucid_tenancy_spec.rb && make core.check`

### PR B2 — runtime: call sites, middleware e jobs (branch `feat/lucid-tenancy-luneta-2`, base `feat/lucid-tenancy-luneta-1`)
**Entrega:** todos os call sites do `Hotel` e `Current.organization` trocados; `TenantMiddleware` e `TenantResolver` substituídos pelo middleware da gem (landing e 404 via `on_missing_tenant`); `tenancy :shared` nos 4 models; jobs `AttendanceNotificationJob` e `PedagogicalStatusAlertJob` corrigidos; jobs do Cloud Tasks (`/tasks`) com `tenancy :shared`.
**Arquivos:** Modify `app/controllers/application_controller.rb`, `app/controllers/public/prospections_controller.rb`, `app/controllers/public/nationalities_controller.rb`, `app/reflexes/application_reflex.rb`, `app/jobs/attendance_notification_job.rb`, `app/jobs/pedagogical_status_alert_job.rb`, `app/models/{organization,admin,audit,subdomain_provisioning}.rb`, `config/initializers/hotel.rb` → removido, `db/seeds.rb`, as 4 navbars e partials que leem `Current.organization` — (até 10 por PR: dividir em B2a runtime de requisição e B2b jobs/seeds/tasks se passar do teto)
**Pronto para prod:** mesmo comportamento observável; jobs passam a rodar no schema certo.
**Valida:** `make core.test && make core.check`

### PR B3 — migrations e provisionamento (branch `feat/lucid-tenancy-luneta-3`, base `feat/lucid-tenancy-luneta-2`)
**Entrega:** `tenancy :tenant|:shared` nas 62 migrations (mudança mecânica de uma linha por arquivo, sem lógica: **exceção ao teto de 10 arquivos, a confirmar na aprovação da spec**, ou dividir em lotes de 10); `Organization::Create` usa `Lucid::Tenancy.provision`; rake de tenant antigas removidas.
**Arquivos:** Modify `db/migrate/*` (62), `app/models/organization/create.rb`, `app/models/organization.rb` — Delete `lib/tasks/tenant_migrations.rake`, `lib/tasks/tenant_schema.rake`, `lib/tenant_migration_context.rb` — Test `spec/models/organization/create_spec.rb`, `spec/lib/tenancy_migrations_spec.rb`
**Valida:** `make core.test && make core.check`

### PR B4 — remover o legado e atualizar docs (branch `feat/lucid-tenancy-luneta-4`, base `feat/lucid-tenancy-luneta-3`)
**Entrega:** `lib/hotel.rb`, `lib/hotel_tenancy.rb`, `lib/tenant_middleware.rb`, `app/services/tenant_resolver.rb` removidos; `spec/support/tenant_setup.rb` e `rails_helper` usando os helpers da gem; `AGENTS.md`/`CLAUDE.md` e `docs/CONTEXT.md` com o vocabulário novo; `docs/guides/` atualizado.
**Arquivos:** Delete `lib/hotel.rb`, `lib/hotel_tenancy.rb`, `lib/tenant_middleware.rb`, `app/services/tenant_resolver.rb` — Modify `spec/support/tenant_setup.rb`, `spec/rails_helper.rb`, `AGENTS.md`, `CLAUDE.md`, `docs/CONTEXT.md`, `modules/core/code/lib/MULTI_TENANT_MIGRATIONS.md`
**Valida:** `grep -rn "Hotel\b\|HotelTenancy\|TenantMiddleware\|TenantMigrationContext" modules/core/code/app modules/core/code/lib modules/core/code/config modules/core/code/spec` vazio `&& make core.check`

## SEQUENCE
Repo `br4zz4/lucid-tenancy`: 1. #<A1> núcleo · 2. #<A2> tenant model e provisionamento · 3. #<A3> migrations · 4. #<A4> middleware · 5. #<A5> jobs, cable e testes · 6. #<A6> gerador, docs e v0.1.0. Merge in this order: #<A1> … #<A6>, depois a tag `v0.1.0`.

Repo luneta (após a tag): 1. #<B1> gem e configuração · 2. #<B2> runtime e jobs · 3. #<B3> migrations e provisionamento · 4. #<B4> remover o legado. Merge in this order: #<B1> #<B2> #<B3> #<B4>.

# definition of done

- [ ] Todo cenário de "acceptance criteria" foi validado (automatizado ou verificado com comando exato)
- [ ] Testes automáticos passando — suíte verde, não só a parte nova (`bundle exec rake test` na gem; `make core.check` no luneta)
- [ ] Toda task do "how" executada
- [ ] Documentação atualizada (ver "documentation")
- [ ] Staging: `staging: none` declarado
- [ ] Cada PR da sequência validado isoladamente (build e testes verdes sem os PRs seguintes)
- [ ] Último PR liga a funcionalidade e remove código temporário (`Hotel` e afins removidos)
- [ ] CI da gem verde em ubuntu 3.2, ubuntu 3.4 e macOS 3.4 com PostgreSQL
- [ ] Tag `v0.1.0` publicada em `br4zz4/lucid-tenancy` e consumida pelo luneta
- [ ] Troca de tenant: bloco, exceção, sem bloco, shared, tabelas compartilhadas (`switching_test.rb`, `model_test.rb`)
- [ ] Enumerable: `each`, `map`, `find`, `count` sem troca, restauração (`collection_test.rb`)
- [ ] Configuração por initializer e por concern, conflito levanta erro (`tenant_test.rb`, `configuration_test.rb`)
- [ ] Identificador: normalização, citação, reservados, inválidos (`identifier_test.rb`)
- [ ] Provisionamento completo e transacional, duplicado recusado (`provisioning_test.rb`)
- [ ] Migrations de tenant rodam em cada tenant e no template, shared uma vez, sem declaração falha, rollback, nunca apaga schema (`migrator_test.rb`)
- [ ] Dump do template e verificação de sincronia (`schema_dump_test.rb`)
- [ ] Middleware: resolução, limpeza (inclusive streaming), tenant ausente, fronteira de caminho, proxies (`middleware_test.rb`, `resolver_test.rb`)
- [ ] Active Job leva o tenant; job `shared`; Action Cable e helpers de teste (`active_job_test.rb`, `action_cable_test.rb`, `test_helpers_test.rb`)
- [ ] Documentação da gem completa: todos os arquivos da seção "Documentação da gem" existem
- [ ] `grep -rn "Hotel\b\|HotelTenancy\|TenantMiddleware\|TenantMigrationContext" modules/core/code/app modules/core/code/lib modules/core/code/config modules/core/code/spec` vazio
- [ ] Jobs de tenant rodam na escola certa (specs dos dois jobs)
- [ ] Migration nova chega a todas as escolas existentes (`tenancy_migrations_spec.rb`)
- [ ] Criar escola provisiona schema completo e subdomínios perigosos são recusados (`organization/create_spec.rb`)
- [ ] Rotas do luneta seguem como hoje (`/up`, `/p`, `/tasks`, `/sysadmin`, `www`, 404) e a suíte inteira está verde

## documentation

- Gem `br4zz4/lucid-tenancy`: todos os arquivos da seção "Documentação da gem" (inglês) e a cópia desta spec.
- `AGENTS.md` / `CLAUDE.md` do luneta: seção de multi-tenancy com o vocabulário novo (`with(tenant:)`, `shared`, `each`, `tenancy :tenant|:shared`), sem `acts_as_tenant` e sem `Hotel`.
- `docs/CONTEXT.md`: termos tenant, shared, template.
- `docs/adr/0006-tenancy-gem-schema-per-tenant-on-postgres.md` (escrito junto com esta spec).
- Skill `br4zz4:rails` (repo `br4zz4/skills`): multi-tenancy com `lucid-tenancy` e a regra de nomes de variáveis.
