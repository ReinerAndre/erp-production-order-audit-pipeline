-- =================================================================================================
-- Projeto: Auditoria e Conciliação de Ordens de Produção (WIP x PA)
-- Dialeto: SQL ANSI / Oracle DW
-- Descrição: Identifica ordens de produção em andamento com etapa final concluída/interrompida
--            mas com pendências em operações intermediárias/retrabalho, prevenindo dupla contagem contábil.
-- =================================================================================================

WITH
-- 1. Seleciona ordens de produção ativas (em andamento no chão de fábrica)
cte_ordens_ativas AS (
    SELECT 
        id_empresa,
        cd_ordem_producao,
        qt_planejada,
        cd_produto
    FROM erp_manufatura.fato_ordem_producao
    WHERE id_empresa = 6
      AND st_ordem = 'P' -- 'P': Em Produção / Em Andamento
),

-- 2. Isola a etapa final do roteiro produtivo (Etapa 60) com status de encerramento ou interrupção
cte_etapa_final AS (
    SELECT 
        oper.id_empresa,
        oper.cd_ordem_producao,
        oper.st_operacao,
        oper.ds_st_operacao,
        oper.qt_produzida,
        ord.qt_planejada                     AS qt_planejada_ordem,
        ROUND((oper.qt_produzida / NULLIF(ord.qt_planejada, 0)) * 100, 2) AS vl_perc_produzido,
        oper.dt_fim_operacao
    FROM erp_manufatura.fato_apontamento_operacao oper
    INNER JOIN cte_ordens_ativas ord
        ON ord.id_empresa = oper.id_empresa
       AND ord.cd_ordem_producao = oper.cd_ordem_producao
    WHERE oper.nr_etapa = 60
      AND oper.st_operacao IN ('E', 'T') -- 'E': Encerrada, 'T': Interrompida/Travada
),

-- 3. Identifica operações anteriores (retrabalhos e fases intermediárias) com apontamentos em aberto/pendentes
cte_etapas_intermediarias AS (
    SELECT 
        oper.id_empresa,
        oper.cd_ordem_producao,
        oper.nr_etapa,
        oper.cd_recurso_maquina,
        oper.st_operacao,
        oper.ds_st_operacao,
        oper.qt_produzida,
        oper.dt_fim_operacao
    FROM erp_manufatura.fato_apontamento_operacao oper
    INNER JOIN cte_ordens_ativas ord
        ON ord.id_empresa = oper.id_empresa
       AND ord.cd_ordem_producao = oper.cd_ordem_producao
    WHERE oper.nr_etapa != 60
      AND oper.st_operacao IN ('F', 'T', 'P') -- 'F': Finalizada c/ Pendência, 'T': Travada, 'P': Em Processo
),

-- 4. Cruza a etapa final com as etapas anteriores para mapear conflitos de apontamento e calcular aging
cte_consolidacao_anomalias AS (
    SELECT 
        fim.id_empresa                        AS id_empresa_etapa_final,
        fim.cd_ordem_producao,
        fim.st_operacao                       AS st_operacao_final,
        fim.ds_st_operacao                    AS ds_st_operacao_final,
        fim.qt_produzida                      AS qt_produto_acabado,
        fim.qt_planejada_ordem,
        fim.vl_perc_produzido,
        fim.dt_fim_operacao                   AS dt_fim_etapa_final,
        CASE 
            WHEN fim.st_operacao = 'T' 
            THEN TRUNC(SYSDATE - fim.dt_fim_operacao) 
            ELSE 0 
        END                                   AS nr_dias_interrompida,
        inter.nr_etapa                        AS nr_etapa_pendente,
        inter.cd_recurso_maquina,
        inter.st_operacao                     AS st_operacao_pendente,
        inter.ds_st_operacao                  AS ds_st_operacao_pendente,
        inter.dt_fim_operacao                 AS dt_fim_etapa_pendente
    FROM cte_etapa_final fim
    INNER JOIN cte_etapas_intermediarias inter
        ON inter.id_empresa = fim.id_empresa
       AND inter.cd_ordem_producao = fim.cd_ordem_producao
)

-- 5. Seleção final com regras de negócio para direcionamento operacional e contábil
SELECT 
    id_empresa_etapa_final,
    cd_ordem_producao,
    st_operacao_final,
    ds_st_operacao_final,
    qt_produto_acabado,
    qt_planejada_ordem,
    vl_perc_produzido,
    dt_fim_etapa_final,
    nr_dias_interrompida,
    nr_etapa_pendente,
    cd_recurso_maquina,
    st_operacao_pendente,
    ds_st_operacao_pendente,
    CASE 
        WHEN vl_perc_produzido < 90 AND st_operacao_final = 'T' THEN
            CASE 
                WHEN vl_perc_produzido < 90 AND st_operacao_final = 'T' AND nr_dias_interrompida >= 12 
                THEN 'Revisar Interrupção'
                ELSE 'Ok'
            END
        ELSE 'Avaliar'
    END AS ds_status_auditoria
FROM cte_consolidacao_anomalias;
