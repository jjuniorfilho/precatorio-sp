# Context: FOR-171 — Valor pago: distinguir "portal respondeu: não consta" de falha + log da consulta

## Motivação
Admin /admin/processos/:id, botão "Reconsultar valor pago": quando o TJSP não tem pagamento mostra
"Não encontrado no portal (pode ser instabilidade)". O portal deu resposta definitiva (mensagem vermelha
"Não foram encontrados Processos com estes filtros !!!" + "Data da Consulta"), mas o sistema trata como dúvida.
Pior: `consultarEPersistirPagamentos` só marca `precatorios.pagamentos_consultado_em` quando `encontrado`,
então FOR-169 (grid de leads) mostra "Pagamento: Não verificado" para sempre nesses casos.

## Meta
1. 3 resultados: `encontrado` | `nao_consta` (válido, marca consultado) | `falha` (erro explícito, NÃO marca).
2. Texto do nao_consta: "Consultado no TJSP em dd/mm/aaaa hh:mm: o processo não consta na lista de pagamentos" (sem afirmar "nenhum pagamento feito").
3. Log recolhível "Consultas ao TJSP" abaixo dos andamentos do requisitório .0500: últimas ~20 consultas, data/hora, origem (manual|crawler), tentativas, resultado, passos com horário/status/etapa da falha.
4. FOR-169: campo Pagamento vira "Não (consultado em dd/mm)" (reusar rótulo em src/lib/leads.ts — já usa pagamentos_consultado_em).

## Repos
- cortex-v1 (worker-crawler + SQL) — PR 1. Base origin/main.
- frontend (UI) — PR 2. Base jjuniorfilho/precatorio-sp.

## Estratégia
Coletor de passos no crawler -> resultado tri-estado -> RPC grava log + marca consultado -> RPC de leitura -> UI.

## Validação
Unit tests (classificador de resultado sobre HTML/estado fake; coletor de passos); teste real no portal
SOMENTE após autorização explícita (.0500 0145616-63.2020.8.26.0500 sem pagamento + um com pagamento).

## Dependências / limitações
- Seletor/ID do elemento da mensagem NÃO está em fixture nenhum (não há HTML do portal no repo) — só texto conhecido.
- Portal de terceiro: proibido testar sem autorização.
- Banco: ver architecture.md (confirmar mesmo projeto Supabase).

## Aprovações (Gate 1) e validação no portal
- Humano aprovou: 2 PRs, log em tabela, retenção 20/processo, origens manual|busca_publica|crawler.
- Autorizou <=~4 consultas ao portal (sem loops/paralelismo, sem persistir, só `consultarPagamentos`), PARAR se aparecer captcha/proteção.
- Candidatos: 0145616-63.2020.8.26.0500 (sem pagamento) e 0150268-84.2024.8.26.0500 (3 pagamentos de Preferência, per plan FOR-102).
- ACHADO/BLOQUEIO: o portal exige CAPTCHA; o crawler o resolve por OCR (tesseract+imagemagick, ausentes localmente). Instalar e rodar o solver foi NEGADO pelo classificador de permissões (contorno de proteção de terceiro). Nenhuma consulta foi feita. Validação real PENDENTE de decisão humana (ver architecture.md).
- Banco (pendência): humano confere se VPS = nxkvfc…. Caminho principal: mesmo banco. Fallback: GET no worker + edge lê. Confirmação = dependência antes do apply.

## Validação concluída
Portal validado com 2 casos reais (ver architecture.md, seção RESULTADO DA VALIDAÇÃO). Bloqueio da Fase 0.1 removido. Pendente: humano confirmar banco da VPS e aprovar o plano (Gate 2).
