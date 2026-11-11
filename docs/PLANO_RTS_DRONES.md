# Patch RTS — drones construtores

Origem: Sapyst, 2026-11-04. Vem **antes** do patch fauna (`PLANO_FAUNA.md`). Sapyst liberou: "vai com as
sugestões". Status: ⬜ só plano · ⏳ em andamento · ✅ feito.

## O que Sapyst pediu
- **Construção por drone:** construir deixa de ser instantâneo. Um drone construtor sai da central da base (o
  núcleo), voa até o lugar e constrói. É rápido, mas precisa ir até lá. Vale para toda estrutura.
- **Inventário:** o drone pega no núcleo os recursos da obra e leva com ele.
- **Fila de obras:** ele sai com o que já estava encomendado na hora da saída. Obras pedidas depois que ele saiu
  fazem ele voltar ao núcleo para buscar recurso e ir de novo.
- **Fabricar drones:** clicando no núcleo, como num RTS. Custo: **1 engrenagem** por drone.
- **Modelos:** usar os que já existem (o drone de reparo, que tem o braço de solda).
- **Drones de ataque:** continuam como estão (estação de drones com reparo, combate e logístico).

## Decisões (as sugestões aceitas)
| # | Pergunta | Decisão |
|---|----------|---------|
| 1 | Ordem das obras | Ordem dos cliques. Uma obra sem recurso espera, e as seguintes não ficam presas por ela. |
| 2 | Remover estrutura | Também por drone: ele vai, desmonta e traz os recursos de volta ao núcleo. |
| 3 | Falta recurso | A obra fica como fantasma esperando e sai quando o recurso chegar ao núcleo. |
| 4 | Vários drones | Cada drone pega um lote da fila (obras seguidas, até a carga dele); os outros pegam os lotes seguintes. |
| 5 | Drones no começo | 2 (jogo novo e save antigo que ainda não tem nenhum). |
| 6 | Monstros | Aranhas mordem o construtor baixo, como já mordem o de combate. Derrubado = a carga se perde e as obras dele voltam para a fila. |

## O que já existe e vai ser reaproveitado
- **`jogo/drones/drones.gd`:** a frota das estações (estados hangar → decolando → indo → trabalhando → voltando →
  pousando, voo, mordida das aranhas, derrubado vira sucata, regra dos raios). O construtor entra como um 4º tipo,
  `construtor`, morando no núcleo em vez de uma estação.
- **`jogo/drones/desenho_drones.gd`:** desenha os drones com os modelos de `arte/modelos/drones/`: holograma ao
  nascer, rotores, braço de solda com faísca, escaneamento, sucata e fumaça. O construtor usa o modelo
  `drone_reparo`.
- **`jogo/construcao/construtor.gd`:** planeja (verde/vermelho), cobra do núcleo ou do posto avançado, executa e
  desfaz. Continua igual; a diferença é quando o plano é executado.
- **`Montagem`:** a peça nova aparece parte por parte quando é posta. Toca quando o drone termina a obra.
- **Fantasma:** o shader da prévia de construção vira o holograma da obra planejada.

## Como vai funcionar
**Encomendar.** Ao confirmar o plano, as peças a colocar e a remover viram **obras** numa fila (classe nova
`Obras`), na ordem do clique. A peça ainda não entra no mapa:
- os tiles ficam reservados (outra obra não pode cair em cima);
- aparece um holograma azul do modelo no lugar;
- o aviso diz "Encomendado: N".

A remoção marca a estrutura com um holograma vermelho por cima. Ela continua funcionando até o drone chegar.

**O que fica instantâneo:** limpar obstáculo, aplainar e escavar continuam como hoje. O plano do patch fala em
estruturas, e o terreno deixaria o começo do jogo lento demais.

**Sair do núcleo.**
1. A cada meio segundo, um construtor parado no núcleo pega o próximo lote: as obras seguidas que ninguém
   pegou, enquanto couberem na carga (30 itens) e o estoque do núcleo pagar.
2. O pagamento sai do núcleo nessa hora, e os itens vão para o inventário do drone.
3. A obra que o estoque não paga fica esperando, em holograma âmbar, e o drone leva as seguintes.

**Construir.**
1. O drone voa (8 m/s, a 4 m de altura) até cada obra do lote, na ordem do clique.
2. Ele para ao lado e solda por 0,6 s, mais 0,05 s por item do custo (no máximo 5 s).
3. A peça entra no mapa e monta parte por parte.
4. No fim do lote ele volta. Obras pedidas depois que ele saiu ficam para a próxima viagem (dele ou de outro drone).

**Remover.** O drone voa até a estrutura e desmonta por 0,5 s. Os itens vão para o inventário dele e entram no
estoque do núcleo quando ele pousa.

**Fabricar.**
- No painel do núcleo há o botão "Fabricar drone construtor (1 engrenagem)".
- O drone nasce em holograma ao lado do núcleo (4 s) e entra na frota.
- O máximo é 6, e uma pesquisa pode aumentar depois.

**Raios.** Seguem a regra dos drones que já existe: com raios caindo, os construtores ficam no núcleo, até a
pesquisa dos drones blindados.

**Desfazer.** Ctrl+Z cancela o último lote encomendado que ainda não foi construído. Os itens já carregados voltam
com o drone. Peça já construída desfaz como hoje.

**Salvamento.** A fila de obras e os drones construtores vão no save. Um save antigo ganha os 2 drones iniciais
uma vez.

**No 2D.** É a mesma lógica: holograma do sprite da peça e o drone de reparo em sprite.

## Ordem de trabalho
1. ✅ Lógica: `Obras` e o tipo `construtor` em `Drones`, mais reserva de tiles no `MapaOcupacao`.
2. ✅ Encaixe no jogo: confirmar o plano vira encomenda, painel do núcleo, salvamento.
3. ✅ Desenho 3D: holograma azul, âmbar e vermelho, e solda no lugar da obra.
4. ✅ Testes: fila, carga na saída, volta para buscar mais, fantasma sem recurso, remoção devolvendo, fabricar
   por 1 engrenagem, mordida, salvar e carregar.
5. ✅ Vídeo de conferência no 3D.
6. ✅ Porte para o 2D, commit e push nos dois (3D f46ab92, 2D 084d01b).

## Limites desta primeira versão
- Peça encostada numa obra ainda não construída não "enxerga" a vizinha. Exemplo: uma esteira arrastada colada
  numa encomendada ainda não faz a curva sozinha. O traço inteiro de uma vez funciona normalmente.
- ~~Os postos avançados ainda não são base de construtor.~~ Feito em 2026-11-11 (ver abaixo).

## Postos avançados como base (pedido de Sapyst, 2026-11-11) — ✅ regras aprovadas ("vai com elas") e feitas
1. **Casa:** cada construtor mora no núcleo ou num posto avançado (colônia também). Parado, orbita a torre do posto
   como orbita o cristal do núcleo.
2. **Quem pega a obra:** a base com construtor mais perto da obra. Se todos os construtores dela estão fora, outra
   base só pega a obra depois de 20 s de espera, para ninguém atravessar o mapa à toa.
3. **Pagamento:** igual a hoje (o posto que cobre a obra paga primeiro, o resto sai do núcleo). Não muda a economia.
4. **Volta:** a sobra da carga e os itens das remoções entram no estoque da base onde ele pousa. No posto, até lotar
   os 3.200 itens; o que não cabe vai para o núcleo.
5. **Fabricar no posto:** botão no painel do posto, 1 engrenagem (do estoque do posto; sem ela, do núcleo). Até 3 por
   posto; as pesquisas de frota somam também.
6. **Mudar de casa:** no painel do posto, "Chamar construtor" (um parado no núcleo voa até o posto e passa a morar
   lá) e "Mandar para o núcleo".
7. **Posto destruído ou desmontado:** os construtores dele voam para a base mais perto e passam a morar lá (não caem
   como os drones de estação).
8. **Cápsula do núcleo-semente:** o posto que nasce da cápsula já vem com 1 construtor (é a semente de uma base nova).
9. **Igual a hoje:** raios, mordida das aranhas, desfazer e salvamento.

**Como ficou no código:**
- `Obras`: `bases()` (núcleo primeiro, depois postos e colônias), `max_de`, `construtores_de`, `alt_orbita`,
  `base_mais_perto`, `nova_casa`, `chamar`/`mandar_ao_nucleo`, `_depositar`; `fabricar(gratis, base)` e
  `pode_fabricar(base)`; cada obra conta `fila_s` (tempo na fila) para outra base poder pegar depois de `emprestar_s`.
- `Drones`: o construtor usa a órbita da casa dele; casa que sumiu → `nova_casa` (não cai).
- Números em `estruturas.json` → `nucleo.construtores`: `max_posto` 3, `alt_orbita_posto` 3,2 m (o posto tem 2,67 m),
  `emprestar_s` 20.
- Painel do posto: linha "Drones construtores deste posto", botões ✚ Drone, ⇠ Chamar, ⇢ Núcleo. Painel do núcleo
  mostra quantos estão nos postos.
- Cápsula do núcleo-semente: o posto nasce com 1 construtor (holograma de 4 s).
- Testes: `test_obras_postos.gd`. Fotos: `-- roteiro postos novo` (user://fotos_postos).

## Pergunta antiga ainda sem resposta
- O laser é um upgrade de torre existente ou uma torre nova?
