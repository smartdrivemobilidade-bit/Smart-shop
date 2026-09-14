# Migrações Supabase

Este diretório registra o histórico de migrações **já aplicado** no projeto Supabase Smart Shop.

O conector disponível nesta transferência expõe a lista de versões/nomes aplicados, mas não fornece o SQL-fonte histórico de cada migration já executada. Por isso:

- `APPLIED_MIGRATIONS.csv` é o manifesto autoritativo das migrações aplicadas.
- O banco Supabase atual é a fonte de verdade do schema.
- Antes de recriar o banco em outro projeto, exporte o schema/migrations pelo Supabase CLI (`supabase db dump` / `supabase migration list`) ou pelo painel/CLI com credenciais próprias.
- Não foi incluída nenhuma senha, `service_role`, JWT secret ou credencial de banco neste pacote.

Projeto atual (não secreto):
- Nome: Smart Shop
- Project ref: `iwbxyhcmcxeaqkkqveni`
- Região do projeto: `us-west-2`
