# Manual Operacional: Auditoria de Ordens de Produção & Integridade WIP/PA

## 1. Contexto e Problema de Negócio

Em ambientes industriais com fluxos de fabricação discretos ou de processos contínuos, desvios operacionais exigem rotas de retrabalho. O ERP modela essas rotas por meio de sequências de etapas (ex.: 10 - Corte, 20 - Usinagem, 30 - Retrabalho, 60 - Embalagem/Finalização).

### Causa Raiz da Anomalia
* A última operação fabril (Etapa 60) é encerrada (`E`) ou interrompida (`T`), registrando a entrada dos itens como Produto Acabado (**PA**).
* Operações intermediárias ou de retrabalho não recebem baixa administrativa pelo chão de fábrica e permanecem abertas (`P`, `T` ou `F`).
* O ERP mantém o status global da ordem como ativa ("Em Produção"), o que retém valores contábeis alocados em Estoque em Processo (**WIP** - *Work in Process*).

### Impacto Contábil
Ocorre a **dupla contagem contábil de estoques**: o mesmo volume físico de insumos e mão de obra fica valorizado simultaneamente na conta de **WIP** e na conta de **PA**, gerando distorção no Balanço Patrimonial e retrabalho na conciliação de fechamento contábil.

---

## 2. Dicionário de Status e Parâmetros

### Status da Operação (`st_operacao`)

| Código | Descrição Operacional | Significado no Processo |
| :---: | :--- | :--- |
| **`E`** | Encerrada | Operação finalizada com apontamento total de tempo e peças. |
| **`T`** | Interrompida / Travada | Operação suspensa temporariamente por problemas de máquina, falta de insumo ou qualidade. |
| **`P`** | Em Processo / Aberta | Operação iniciada no chão de fábrica e ainda em andamento. |
| **`F`** | Finalizada c/ Pendência | Registro de encerramento parcial que ainda requer validação de saldo. |

---

## 3. Matriz de Auditoria e Lógica de Classificação

O script avalia o percentual realizado em relação à quantidade planejada (`vl_perc_produzido`), a situação da etapa final e o tempo de estagnação (`nr_dias_interrompida`).

[Etapa 60 = 'T' e Perc < 90%?]
                                  /            \
                                SIM            NÃO
                                /                \
                   [Dias Parado >= 12?]      Status: "Avaliar"
                         /        \
                       SIM        NÃO
                       /            \
    Status: "Revisar Interrupção"   Status: "Ok"
| Classificação Gerada | Critério de Regra | Severidade | Ação Esperada |
| :--- | :--- | :---: | :--- |
| **Revisar Interrupção** | `st_operacao_final = 'T'`<br>`vl_perc_produzido < 90%`<br>`nr_dias_interrompida >= 12` | 🔴 **Alta** | Investigar causa de bloqueio com supervisão fabril. Se não houver retorno da produção, realizar refugo ou encerramento manual. |
| **Avaliar** | `st_operacao_final = 'E'` com etapas intermediárias ainda abertas | 🟡 **Média** | Confirmar entrada física no armazém e encerrar administrativamente as etapas anteriores para liberar o saldo de WIP. |
| **Ok** | `st_operacao_final = 'T'`<br>`vl_perc_produzido < 90%`<br>`nr_dias_interrompida < 12` | 🟢 **Baixa** | Ordem dentro do ciclo operacional tolerável; manter apenas o monitoramento rotineiro. |

---

## 4. Guia de Ação Operacional (Playbook)

### Fluxo para o PCP (Planejamento e Controle de Produção)
1. **Filtro Primário:** Executar a consulta filtrando registros com status `Revisar Interrupção`.
2. **Checagem de Piso:** Validar com o operador do centro de trabalho (`cd_recurso_maquina`) o motivo da parada superior a 12 dias.
3. **Decisão:**
   * **Retomar:** Reabrir apontamento e concluir a etapa 60.
   * **Cancelar Saldo:** Realizar a baixa técnica das sobras/refugos e fechar a ordem no sistema.

### Fluxo para a Controladoria & Custos
1. **Rotina Pré-Fechamento:** Executar a consulta no período de corte mensal (D-3).
2. **Conciliação de Inventário:** Identificar todas as ordens com status `Avaliar`.
3. **Saneamento Contábil:** Solicitar ao PCP o encerramento em lote de todas as etapas intermediárias já superadas fisicamente, eliminando a duplicidade entre as contas de WIP e PA.

---

## 5. Parâmetros de Execução e Customização

Caso necessite adaptar o script para diferentes realidades de fábrica, altere as seguintes variáveis diretamente no SQL:

```sql

-- 1. Identificador da etapa final do roteiro padrão da empresa:
WHERE oper.nr_etapa = 60

-- 2. Limiar de tolerância de parada (dias) para escalar ao PCP:
AND nr_dias_interrompida >= 12

-- 3. Meta mínima de conclusão física:
WHEN vl_perc_produzido < 90
```
