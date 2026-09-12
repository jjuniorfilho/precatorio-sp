-- Diagnóstico ad-hoc (leitura pura, não altera nada) — separa os erros de crawler_queue por
-- categoria e por hora do dia (BRT), pra confirmar/refutar a hipótese de bloqueio do TJSP por
-- padrão de sessão (getSession() novo a cada lote + 3 conexões concorrentes com o mesmo
-- JSESSIONID, loop 24/7) vs. manutenção noturna do TJSP vs. o bug de roteamento já investigado
-- em djen_link_diag.sql (eproc/"outro" caindo no e-SAJ sem evidência).
-- Rodar no SQL Editor. Ajustar o INTERVAL se quiser janela maior/menor.

-- 1) Categoria x hora do dia (agregando todos os dias — mostra se é padrão recorrente)
select
  extract(hour from updated_at at time zone 'America/Sao_Paulo')::int as hora_brt,
  case
    when erro ilike '%não retornou página de detalhe%'
      or erro ilike '%requisitório não retornou%'          then 'sem_ficha_detalhe'  -- rota errada OU manutenção 200
    when erro ilike '%HTTP 429%'                            then 'http_429'          -- rate limit explícito
    when erro ilike '%HTTP 5%'                               then 'http_5xx'          -- erro de servidor
    when erro ilike '%excedeu o teto%'                       then 'job_timeout'       -- travou (não é o TJSP)
    when erro ilike '%timeout%' or erro ilike '%AbortError%'
      or erro ilike '%UND_ERR%' or erro ilike '%ECONNRESET%' then 'timeout_rede'
    else 'outro'
  end as categoria_erro,
  count(*) as n
from crawler_queue
where erro is not null
  and updated_at >= now() - interval '7 days'
group by 1, 2
order by 1, n desc;

-- 2) Série temporal (dia+hora) — mostra se está concentrado numa janela fixa (ex.: manutenção
-- noturna do TJSP) ou é ruído espalhado ao longo do dia
select
  date_trunc('hour', updated_at at time zone 'America/Sao_Paulo') as hora,
  case
    when erro ilike '%não retornou página de detalhe%'
      or erro ilike '%requisitório não retornou%'          then 'sem_ficha_detalhe'
    when erro ilike '%HTTP 429%'                            then 'http_429'
    when erro ilike '%HTTP 5%'                               then 'http_5xx'
    when erro ilike '%excedeu o teto%'                       then 'job_timeout'
    when erro ilike '%timeout%' or erro ilike '%AbortError%'
      or erro ilike '%UND_ERR%' or erro ilike '%ECONNRESET%' then 'timeout_rede'
    else 'outro'
  end as categoria_erro,
  count(*) as n
from crawler_queue
where erro is not null
  and updated_at >= now() - interval '3 days'
group by 1, 2
order by 1 desc, n desc;

-- 3) Amostra de mensagens cruas por categoria (pra validar se o bucket "outro" esconde algo
-- relevante, e ver o texto exato de "sem_ficha_detalhe" — se vier junto com trecho de HTML de
-- manutenção, confirma a teoria; se for CNJ que claramente não é e-SAJ, confirma o bug de rota)
select erro, count(*) as n
from crawler_queue
where erro is not null
  and updated_at >= now() - interval '3 days'
  and erro not ilike '%não retornou página de detalhe%'
  and erro not ilike '%requisitório não retornou%'
  and erro not ilike '%HTTP 429%'
  and erro not ilike '%HTTP 5%'
  and erro not ilike '%excedeu o teto%'
  and erro not ilike '%timeout%' and erro not ilike '%AbortError%'
group by 1
order by n desc
limit 30;
