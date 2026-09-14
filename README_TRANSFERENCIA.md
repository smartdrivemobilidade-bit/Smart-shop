# SMART SHOP — TRANSFERÊNCIA PARA CHATGPT WORK

Data da transferência: **14/09/2026**

Este pacote concentra a versão de trabalho mais recente do Smart Shop e o contexto técnico necessário para continuar o desenvolvimento no ChatGPT Work.

## 1. Arquitetura atual

O Smart Shop está dividido em quatro experiências separadas:

1. `apps/cliente/index.html` — App Cliente / marketplace público.
2. `apps/lojista/index.html` — Painel Web do Lojista.
3. `apps/entregador/index.html` — App do Entregador.
4. `apps/master/index.html` — Painel Master/administrativo.

Não voltar ao modelo antigo de uma única interface com botões para trocar Cliente/Lojista/Entregador/Master.

## 2. O que já está pronto

### Cliente
- catálogo público antes do login;
- lojas, categorias, produtos, busca e página do produto;
- login exigido para ações privadas;
- carrinho de uma loja por pedido no MVP;
- checkout com validação server-side;
- endereço, cupom, modalidade e pedido;
- pedidos, histórico e suporte;
- favoritos;
- Home evoluída com categorias ampliadas, incluindo Gás e Água;
- base visual/comercial para banners e entrega no mesmo dia;
- lógica de status de horário/“Entrega hoje” no frontend.

### Lojista
- candidatura/aprovação;
- vínculo com loja;
- configurações da loja;
- produtos;
- pedidos;
- fluxo de preparação/coleta;
- suporte/notificações;
- tela de conta própria de lojista;
- edição amigável de horário de funcionamento.

### Entregador
- candidatura, documentos e aprovação;
- veículo;
- online/offline;
- ofertas;
- aceite;
- chegada à loja;
- código de coleta;
- início da entrega;
- código de entrega;
- suporte/notificações;
- carteira demonstrativa;
- fundação de GPS/geofencing.

### Master
- aprovações de parceiros/documentos;
- papéis administrativos;
- cupons;
- banners;
- suporte;
- operações;
- financeiro;
- auditoria;
- base para campanhas, indicações e qualidade das lojas.

### Recursos de crescimento já preparados no banco
- banners interativos para marketplace/loja/categoria/produto/cupom/campanha;
- tipos de lojista: MEI, empresa/LTDA e vendedor individual;
- indique um amigo com qualificação após primeira compra válida;
- indique uma loja para prospecção;
- lojas favoritas/seguidores;
- Loja Destaque por métricas;
- avaliações e resumo por loja;
- horários inteligentes;
- entrega no mesmo dia, cutoff e expressa;
- campanhas sazonais;
- cupons por escopo/funding;
- métricas de mais vendidos/descoberta.

## 3. O que falta / prioridade

### Prioridade crítica
1. Corrigir e retestar a transição `picked_up -> out_for_delivery` do pedido E2E.
2. Finalizar o pedido E2E preservado somente após corrigir essa transição.
3. Endurecer GPS/geofence para coleta e destino e definir política de exceção.
4. Corrigir definitivamente textos de notificação por destinatário.
5. Revisar os avisos de segurança Supabase descritos em `supabase/CURRENT_DATABASE_STATE.md`.

### Produto
6. Conectar completamente os recursos de growth às telas Cliente/Master/Lojista.
7. Banners: CRUD Master completo, upload de imagem e targets produto/cupom/campanha.
8. Cadastro de lojista: formulário condicional por tipo jurídico.
9. Indique amigo/loja: interfaces de cliente e gestão Master.
10. Loja Destaque: tela de critérios e exibição pública.
11. Página de loja completa: capa, nota, horário, área atendida, modalidades e catálogo.
12. “Lojas abertas agora”, mais vendidos, melhor avaliados, novidades e promoções.
13. “Comprar novamente”.
14. Cupons locais completos no Master.
15. Programa de fidelidade: manter desativado até definir regras financeiras.
16. Pagamento real somente depois de estoque, cancelamento, entrega e conciliação estarem estáveis.

## 4. Supabase

Projeto atual:
- nome: **Smart Shop**
- project ref: `iwbxyhcmcxeaqkkqveni`
- URL pública do projeto: `https://iwbxyhcmcxeaqkkqveni.supabase.co`

As chaves foram removidas dos HTMLs deste pacote.
Substitua `YOUR_SUPABASE_PUBLISHABLE_KEY` por uma **publishable key** válida quando for testar localmente.

**Nunca use `service_role` em HTML, JS do cliente ou repositório público.**

O histórico de migrações aplicadas está em:
`supabase/migrations/APPLIED_MIGRATIONS.csv`

Observação: o conector utilizado permite listar as migrations aplicadas, mas não recuperar automaticamente o SQL-fonte histórico completo de cada migration. O banco atual deve ser considerado a fonte de verdade. Antes de mover para outro Supabase, gere um dump com Supabase CLI.

## 5. Como executar localmente

Os painéis são HTML/JS estáticos que usam Supabase.

No diretório raiz:

```bash
python -m http.server 8080
```

Depois abra, por exemplo:

- Cliente: `http://localhost:8080/apps/cliente/`
- Lojista: `http://localhost:8080/apps/lojista/`
- Entregador: `http://localhost:8080/apps/entregador/`
- Master: `http://localhost:8080/apps/master/`

Não testar recursos PWA completos via `file://`; use HTTP/HTTPS.

## 6. Como testar

Ordem recomendada:

1. Catálogo público sem login.
2. Login de cliente.
3. Favoritos/carrinho.
4. Checkout.
5. Pedido no painel Lojista.
6. Lojista: pago -> preparando -> pronto -> solicitar entregador.
7. Entregador: oferta -> aceite -> chegada -> coleta por PIN.
8. **Validar com atenção `picked_up -> out_for_delivery`.**
9. Cliente acompanha histórico.
10. Entrega por PIN.
11. Validar financeiro/ledger.
12. Testar cancelamento/devolução.
13. Testar suporte/notificações.
14. Testar Master e permissões por papel.

Não criar um novo pedido apenas para contornar o bug do fluxo atual; corrigir primeiro a transição.

## 7. Situação do GitHub Pages

Repositório:
`smartdrivemobilidade-bit/Smart-shop`

Branch padrão: `main`.

O GitHub Pages publicado **não representa a V4 atual**. O repositório público ainda contém uma versão demonstrativa/antiga com `index.html`, `manifest.webmanifest`, `sw.js` e `LEIA-ME.txt`.

Não substituir o GitHub Pages pela V4 até:
- concluir o E2E;
- revisar segurança;
- conferir que nenhum segredo foi embutido;
- escolher quais painéis serão públicos e quais exigirão rota/domínio separado.

A pasta `deploy/github_pages/pwa_legado_referencia` existe somente como referência histórica de PWA.

## 8. Dados de teste

Bella Moda e Store Tech são lojas **fictícias de demonstração**. Endereços, horários e cadastros de teste não devem ser interpretados como estabelecimentos reais.

Nenhuma senha, chave secreta, `service_role`, token privado ou dado pessoal real deve ser colocado neste pacote.

## 9. Estrutura do pacote

```text
apps/
  cliente/
  lojista/
  entregador/
  master/
config/
docs/
supabase/
  migrations/
deploy/
  github_pages/
historico_relevante/
README_TRANSFERENCIA.md
MANIFESTO_ARQUIVOS.txt
SHA256SUMS.txt
```

## 10. Regra para continuidade no ChatGPT Work

Antes de modificar:
1. ler este README;
2. ler `docs/Smart_Shop_Escopo_Completo_Projeto_V2 (1).docx`;
3. conferir o estado atual do Supabase;
4. preservar os quatro produtos separados;
5. não publicar V4 no GitHub Pages antes do E2E e da revisão de segurança;
6. não inserir segredos no frontend;
7. trabalhar com migrations versionadas para qualquer mudança de banco.
