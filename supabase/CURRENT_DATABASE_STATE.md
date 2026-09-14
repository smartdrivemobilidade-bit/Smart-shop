# Estado atual do Supabase

## Núcleo já implementado
- autenticação e perfis;
- lojas, membros de loja e produtos;
- endereços;
- pedidos e itens;
- máquina de estados do pedido;
- entrega Smart Shop e entregadores;
- códigos de coleta/entrega;
- GPS/geofencing foundation;
- notificações;
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

## Avisos de segurança ainda pendentes de revisão
- tabela `order_verification_codes` com RLS e sem policy pública (intencionalmente restrita, revisar arquitetura);
- algumas funções `SECURITY DEFINER` executáveis por usuários autenticados devem ser auditadas função a função;
- proteção de senha vazada no Supabase Auth estava desabilitada na última revisão.

Não alterar permissões de funções em lote sem testar cliente, lojista, entregador e Master.
