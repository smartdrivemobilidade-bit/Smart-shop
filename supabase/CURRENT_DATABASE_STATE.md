# Estado atual do Supabase

Atualizado em 14/09/2026. Projeto: `iwbxyhcmcxeaqkkqveni`.

## Núcleo implementado

- autenticação e perfis;
- lojas, membros de loja e produtos;
- endereços;
- pedidos e itens;
- máquina de estados do pedido;
- entrega Smart Shop e entregadores;
- códigos de coleta/entrega;
- GPS e geofence validados no servidor;
- notificações por destinatário;
- checkout server-side, cotação, idempotência e estoque;
- cupons e resgates;
- financeiro, comissão e ledger;
- cancelamentos, devoluções e ocorrências;
- avaliações;
- suporte/tickets e respostas;
- banners da Home;
- favoritos;
- papéis administrativos;
- histórico/auditoria.

## Growth/marketplace regional já migrado

- indicação de amigo;
- indicação de loja;
- seguidores/lojas favoritas e notificações;
- horários estruturados das lojas;
- entrega no mesmo dia / cutoff / expressa;
- métricas de qualidade / Loja Destaque;
- campanhas sazonais e alvos;
- escopo e funding de cupons;
- métricas de descoberta / vendas;
- tipos de lojista (MEI, empresa, individual).

## Correções críticas verificadas

- transição `picked_up -> out_for_delivery` validada;
- erro de agregação UUID no fechamento financeiro corrigido;
- pedido E2E preservado `SS2A7AFC90` concluído como `delivered`;
- liquidação E2E conferida com três lançamentos de ledger;
- notificações separadas para cliente, lojista e entregador;
- geofence exigido na chegada à loja, coleta e entrega;
- raio padrão de 200 m, precisão máxima aceita de 150 m e evento válido por 15 minutos;
- quando o endereço ainda não tem coordenadas, o GPS continua obrigatório e a exceção é registrada automaticamente;
- fluxo completo de geofence testado em transação reversível.
- cadastro de lojista condicionado ao tipo MEI, Empresa/LTDA ou Vendedor individual;
- documentos obrigatórios ajustados por tipo jurídico;
- aceite dos termos registrado com data e versão;
- permissões da tabela de candidaturas corrigidas para `SELECT/INSERT/UPDATE` autenticado, sempre sob RLS;
- aprovação de vendedor individual validada de ponta a ponta em transação reversível.

## Revisão dos avisos de segurança

### Códigos de verificação

A tabela `order_verification_codes` continua inacessível diretamente para `anon` e `authenticated`. A intenção foi documentada com policy RLS restritiva e falsa. Os códigos só devem ser acessados pelos RPCs autorizados.

### Funções SECURITY DEFINER

As 42 funções apontadas pelo advisor foram revisadas quanto a permissões e controles internos:

- nenhuma está executável por `anon`;
- RPCs de cliente e entregador verificam `auth.uid()`, propriedade do recurso e estado permitido;
- RPCs administrativos verificam os papéis Master/Admin/Operações/Suporte/Financeiro conforme a operação;
- funções auxiliares de RLS retornam apenas verificações de vínculo ou papel;
- `get_checkout_settings()` expõe somente valores públicos de frete para usuários autenticados.

O advisor continua exibindo os 42 avisos porque detecta estruturalmente qualquer função `SECURITY DEFINER` executável por `authenticated`, mesmo quando a chamada é intencional e protegida internamente. Não revogar essas permissões em lote: isso quebraria checkout, entregas, suporte e os painéis.

### Pendente no painel Supabase

A proteção contra senhas vazadas ainda precisa ser habilitada manualmente em **Authentication > Security and Protection > Leaked password protection**. Essa configuração não é uma migration SQL.

## Regra operacional

Toda alteração de banco deve ser aplicada por migration versionada e registrada em `supabase/migrations/APPLIED_MIGRATIONS.csv`. Antes de publicar a V4, repetir os testes dos quatro produtos e a revisão de segredos.


## Indicações de amigos e lojas (14/09/2026)

- Fluxo público conectado por RPCs autenticadas: criação de código próprio, vínculo de código recebido e envio de loja para prospecção.
- Indicação de amigo é qualificada automaticamente somente após o primeiro pedido válido alcançar `delivered`; recompensa financeira/cupom permanece sem regra configurada.
- Gestão Master/Admin/Operations disponível para acompanhar indicações e atualizar o funil de lojas.
- Privilégios diretos excessivos removidos das tabelas `referral_codes`, `referrals` e `store_referrals`; clientes autenticados mantêm apenas leitura filtrada por RLS, e mutações passam por funções `SECURITY DEFINER` com validação e `search_path` fixo.
- Políticas legadas conflitantes foram removidas e as chaves estrangeiras usadas pelo fluxo receberam índices.
- Perfil anônimo não possui privilégios nessas tabelas nem execução das RPCs.
- Migrations aplicadas: `20260914214843_smart_shop_v4_referrals_secure_workflows.sql` e `20260914215139_smart_shop_v4_referrals_policy_cleanup_indexes.sql`.


## Performance, RLS e privilégios Growth (14/09/2026)

- Eliminados os avisos ativos de `auth_rls_initplan`, chaves estrangeiras sem índice e políticas permissivas duplicadas, preservando os acessos funcionais.
- Privilégios `REFERENCES`, `TRIGGER` e `TRUNCATE` foram removidos das tabelas Growth expostas; cada papel mantém somente as operações necessárias.
- CRUD de cupons e campanhas foi validado com papel Master em transação revertida, sem dados residuais.
- Migrations aplicadas: `20260914215933_smart_shop_v4_rls_performance_hardening.sql` e `20260914220211_smart_shop_v4_growth_table_least_privileges.sql`.
