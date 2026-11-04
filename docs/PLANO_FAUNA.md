# Patch fauna — catálogo de ideias

Origem: conversa com Sapyst em 2026-11-04. Este arquivo junta tudo o que foi falado, para planejar a ordem
juntos antes de codar. Vem **depois** do patch RTS dos drones construtores (ver `PLANO_RTS_DRONES.md`).

**Tom:** o planeta inteiro é alienígena. Pássaros, ratos, vagalumes e árvores já são fauna e flora de outro
mundo, mas tudo **bem pé no chão** (crível, natural, nada fantasioso). Aranhas e larvas são só as espécies mais
agressivas do mesmo ecossistema. Em vez de "natureza contra aliens", é um ecossistema só, com cadeia alimentar,
territórios e reação ao que a IA do jogador faz. Detalhes levemente estranhos (plumagem, olhos, padrão de luz)
sem virar fantasia.

**Regra de custo:** tudo leve para o celular — insetos como pontinhos, bandos desenhados em lote, ciclos lógicos
baratos.

Legenda: ✅ feito · ⏳ parcial · ⬜ só ideia · (S) = pedido de Sapyst · (C) = sugestão minha

---

## 1. Pássaros ✅ (primeira peça, feita)
- ✅ (S) Modelo de malha única com penas, 5 espécies (pardelo, cobrico, azulão, rubro, planador), algumas coloridas.
- ✅ (S) Animações: voo, planar, parado, bicando, pousar (de trás pra frente = decolar), 16 direções no 2D.
- ✅ (S) Sons por espécie (canto, grito do planador, revoada).
- ✅ (S) Comportamento em massa (boids): bandos que voam juntos, pousam nas copas e no chão, se juntam.
- ✅ (S) Fogem do fogo, da rajada de vento, de monstros, de tiros, explosões e raios.
- ✅ (S) Carregam sementes de área saudável para chão morto (queimado, corroído, limpo) → muda.
- ✅ (S) Noite (dormem) e migração por estação real.
- ⬜ Conferir FPS no celular com até 90 pássaros; ver o planador pousar e a semente brotando em vídeo.

## 2. Comportamento das espécies alien (S)
- ⬜ Cada espécie com comportamento próprio entre os seus (perfil `comportamento` no `inimigos.json`).
  - (C) Aranhas caçam em grupo e abrem ninhos novos; larvas ficam perto da cratera, cospem de longe, corroem o chão.
- ⬜ Procriação por regra própria.
  - (C) Aranhas: pela poluição que o ninho absorve (como hoje). Larvas: precisam de chão corroído / comem árvore
    morta e matéria dissolvida (a corrosão vira comida).
- ⬜ Brigas e **guerra entre espécies alien** (tabela `relacoes`, ex.: aranha × larva = hostil).
  - (C) Territórios (teia = canal R, corrosão = canal G da `Infestacao`) se empurram; quando o chão de um ninho
    encosta no de outra espécie, começa a guerra. Bando de aranhas invadindo cratera, larva cuspindo em ninho,
    território vencedor cobrindo o do perdedor.
  - (C) O jogador pode usar isso: deixar duas espécies se desgastando, ou eliminar uma e a outra domina.

## 3. Vida pequena (S)
- ⬜ Insetos: pontinhos com rastro curto, sem detalhe.
- ⬜ **Vagalumes à noite:** luz micro que pulsa e se destaca no escuro, sobre a grama e perto da água.
- ⬜ **Moscas** voando sobre zonas mortas — só onde há vida biológica morta.

## 4. Ciclo da morte (S)
- ⬜ Animais morrem e o corpo fica no lugar (rato, pássaro, aranha, larva).
- ⬜ Apodrece em etapas (inteiro → inchado → ossos) e some; moscas pairam enquanto houver carcaça.
- ⬜ (C) A podridão deixa o chão mais fértil (plantas brotam ali primeiro).
- ⬜ (C) Animal grande morto atrai carniceiros.

## 5. Frutas, sementes e reflorestamento (S)
- ⬜ Frutas caindo embaixo de árvores e **arbustos**.
- ⬜ Ratos e pássaros comem as frutas e espalham sementes.
- ⏳ Semente → muda (feito) → árvore jovem → adulta, seguindo as estações; chão morto se recupera sozinho se a
  causa sumir.
- ⬜ (C) Estrutura de viveiro para o jogador ajudar.

## 6. Ratos e pequenos animais (S)
- ⬜ Vivem em arbustos e campos, fogem das larvas e do ácido, enterram sementes.
- ⬜ São presa dos aliens (liga com o item 2).

## 7. Mais pássaros e migração (S)
- ⏳ Vários tipos (5 feitos); migração feita na lógica.
- ⬜ (C) Revoadas grandes na troca de estação; no inverno alguns tipos vão embora e outros chegam.

---

## Ideias extras para o ambiente "vivo" (C)
Sugeridas quando Sapyst perguntou "quais mais ideias?". Nenhuma aprovada ainda.

**Plantas que reagem**
- Folhas caindo no outono, juntando no chão e levadas pelo vento.
- Chuva deixa a grama mais verde e alta por uns dias; na seca amarela e o fogo pega mais fácil.
- Flores por estação, abrindo de dia e fechando à noite.
- Juncos e algas na margem; água parada ganhando limo.

**Pequenos sinais de vida**
- Pegadas e trilhas onde bichos passam muito (grama pisada).
- Tocas e ninhos: buracos de rato, ninhos nas árvores, cupinzeiros, com bicho entrando e saindo.
- Sons ambientes por bioma e hora: pássaros de manhã, grilos à noite, sapos perto da água depois da chuva;
  silêncio estranho perto de ninhos e crateras (o silêncio avisa que tem algo errado).
- Peixes pulando nos lagos; na água poluída aparecem mortos boiando.

**Natureza reagindo à IA do jogador**
- A fauna se afasta do barulho e da poluição; em volta da fábrica fica quieto e cinza.
- Recuperação em etapas quando a área é limpa: insetos → mato → ratos → pássaros → árvores.
- Espécies que se adaptam à fábrica: ninho em torre velha, rato roendo cabo.

**Ciclos e eventos raros**
- Enxames de insetos no verão úmido, chuva de sementes ao vento.
- Noite: olhos brilhando no mato, a lua mudando a luz.
- Depois de tempestade: galhos caídos, poças, cogumelos brotando.

**Criaturas maiores (mais tarde)**
- Herbívoros grandes em manada, migrando e fugindo de predadores e do fogo.
- Predadores nativos que caçam ratos e herbívoros e brigam com aranhas e larvas.

---

## Próximo passo
Escolher com Sapyst a ordem dos itens 2–7 (e quais extras entram) e escrever o plano de implementação de cada
um (dados, o que aparece na tela, custo no celular, testes).
