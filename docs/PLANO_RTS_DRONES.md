# Patch RTS — drones construtores

Origem: Sapyst, 2026-11-04. Vem **antes** do patch fauna (`PLANO_FAUNA.md`). Ainda não começou; espera as
respostas das perguntas abertas abaixo.

## O que Sapyst pediu
- **Construção por drone:** construir deixa de ser instantâneo. Um drone construtor sai da central da base, voa
  até o lugar e constrói. É rápido, mas precisa ir até lá. Vale para toda estrutura.
- **Inventário:** o drone pega na base os recursos da obra e leva com ele.
- **Fila de obras:** ele sai com o que já estava encomendado na hora da saída. Obras pedidas depois que ele saiu
  fazem ele voltar à base para buscar recurso e ir de novo.
- **Fabricar drones:** clicando na base, como num RTS. Custo: **1 engrenagem** por drone.
- **Modelos:** usar os que já existem.
- **Drones de ataque:** continuam como estão (base de criação de drones + drones de ataque já existentes).

## Perguntas em aberto (com a minha sugestão)
| # | Pergunta | Sugestão |
|---|----------|----------|
| 1 | Ordem das obras: ordem dos cliques ou a mais perto primeiro? | Ordem dos cliques |
| 2 | Remover estrutura também precisa de drone? | Sim, e ele traz os recursos de volta |
| 3 | Falta recurso na base: a obra fica como fantasma esperando ou é cancelada? | Fantasma esperando |
| 4 | Vários drones: cada um pega uma obra ou dividem uma obra grande? | Cada um pega uma |
| 5 | Quantos drones no começo? | 2 |
| 6 | Aranhas e larvas podem atacar o drone construtor? | Sim (construir longe fica arriscado) |

## Para reaproveitar
- `jogo/drones/drones.gd`: frota de reparo/defesa atual.
- Modelos de drone já existentes em `arte/modelos/`.

## Pergunta antiga ainda sem resposta
- O laser é um upgrade de torre existente ou uma torre nova?
