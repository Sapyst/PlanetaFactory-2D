# Patch fauna — plano em fases

Origem: conversas com Sapyst em 2026-11-04. Aqui estão as ideias de Sapyst (S) e as minhas (C), juntas e ordenadas
por **dependência** e **custo**, para que nenhuma fase precise desmontar o que a anterior fez. Vem depois do patch
RTS (`PLANO_RTS_DRONES.md`, feito).

**Tom:** o planeta inteiro é alienígena, mas tudo é **bem pé no chão** (crível, natural, nada fantasioso).
Pássaros, ratos, vagalumes e árvores já são fauna e flora de outro mundo. Aranhas e larvas são só as espécies mais
agressivas do mesmo ecossistema. É um ecossistema só, com cadeia alimentar, territórios e reação ao que a IA do
jogador faz.

Legenda: ✅ feito · ⏳ parcial · ⬜ a fazer · (S) pedido de Sapyst · (C) sugestão minha.
Custo no celular: **baixo** (efeito perto da câmera, sem lógica nova), **médio** (lógica leve por chunk),
**alto** (muitos bichos com lógica própria).

---

## Regras para não quebrar nada no caminho
1. **Uma fundação primeiro (fase 0).** Todo bicho novo se registra num índice espacial comum e avisa quando morre
   ou come. Assim os sistemas novos conversam pelo índice e pelos eventos, nunca mexendo por dentro uns dos outros.
   Sem isso, cada fase nova teria de reabrir o código das anteriores, e é aí que as funções quebram.
2. **Lógica pura separada do desenho.** É o padrão que o jogo já usa (`Passaros` + `DesenhoPassaros`,
   `Colonia` + `DesenhoColonia`). A lógica é testável sem janela, e o 3D e o 2D só leem o resultado.
3. **Reaproveitar, não duplicar.** Os efeitos pequenos entram no `PoolEfeitos`/`EfeitoAmbiente` que já existe:
   ativo só perto da câmera, com multimesh. Os vagalumes da flor luminosa, os esporos e as brasas já usam esse
   pool.
4. **Números no `fauna.json`**, com uma chave `liga` por sistema. Se algo pesar no celular, desliga-se pelos dados
   sem mexer no código.
5. **Save compatível.** Cada sistema salva a sua chave com padrão vazio, então um save antigo carrega sem erro.
6. **Cada fase fecha inteira:** testes, porte para o 2D, a bateria completa nos dois e o vídeo de conferência,
   antes de a próxima começar.
7. **Os aliens ficam por último entre os sistemas centrais.** A Colônia é o que segura o combate. Ela só muda
   depois que o ecossistema em volta estiver estável, e aí as presas (ratos) e as carcaças já existem para ela usar.

---

## Fase 0 — Fundação do ecossistema ✅ · custo baixo · não muda nada na tela
- **`Ecossistema`** (lógica pura, `jogo/ambiente/ecossistema.gd`):
  - índice espacial por chunk de quem está vivo (tipo, posição);
  - consulta `perto(centro, raio, tipo)`;
  - lista de **fontes de comida** (fruta, semente, carcaça);
  - eventos `morreu`, `comeu`, `fugiu`.
- **Adaptadores:**
  - os `Passaros` se registram no índice;
  - a `Colonia` avisa `morreu` (o evento `aranha_morta` já existe; falta a larva).
  - Nenhum comportamento muda.
- **Orçamento por distância:**
  - perto da câmera, bicho com lógica completa;
  - longe, só a contagem por chunk (é assim que o celular aguenta).
- **Por que primeiro:** frutas, carcaças, ratos, moscas e aliens dependem disso.
- **Feito:**
  - `jogo/ambiente/ecossistema.gd` com as fontes "passaro", "alien" e "toca".
  - A saúde do chão saiu dos `Passaros` e foi para o `Ecossistema`; os pássaros só chamam.
  - A morte de aranha e de larva vira o evento `morreu`.
  - A comida vai no save.
- **Bug corrigido de passagem:** no jogo, os pássaros eram criados antes do ambiente. Por isso não viam fogo, cinza
  nem chão morto, e nunca plantavam semente. Nos testes funcionava porque lá o ambiente é passado.

## Fase 1 — Vida pequena e noite viva ✅ · custo baixo · só leitura do mundo
- (S) **Vagalumes à noite** sobre a grama e perto da água: pontinho com luz micro que pulsa e se destaca.
  - Já existem vagalumes na flor luminosa; esta fase estende o mesmo efeito.
- (S) **Insetos de dia:** pontinhos com rastro curto, sem detalhe.
- (C) **Sons de ambiente por bioma e hora:**
  - pássaros de manhã, grilos à noite;
  - sapos perto da água depois da chuva;
  - silêncio estranho perto de ninhos e crateras.
- (C) Olhos brilhando no mato à noite (sem bicho ainda: só o brilho, raro).
- **Por que aqui:** só lê o clima, a hora, o bioma e os ninhos. Não muda nenhuma regra, e o risco é quase zero.
- **Feito:** `DesenhoVidaPequena`.
  - Enxames ficam presos em tiles fixos do mundo (sorteio por hash), refeitos só quando a câmera anda.
  - O desenho usa 3 MultiMesh, um buffer por quadro, com orçamento de 120 vagalumes e 90 insetos.
  - Os sons novos são `amb_grilos` e `amb_insetos_dia` (laços) e o `sapo` (3 variações).
  - No 2D, `VidaPequena2D` desenha os mesmos pontos em pixel, numa camada acima do escuro da noite.
  - Os números e o liga/desliga ficam em `fauna.json → vida_pequena`.
- **Mudou do plano:** não entrou no `PoolEfeitos`. Aquele pool cria uma planta inteira por efeito (a flor, o
  cogumelo); para centenas de pontinhos ele pesaria muito mais que um MultiMesh. Os vagalumes da flor luminosa
  continuam lá.

## Fase 2 — Plantas que reagem ✅ · custo baixo · shaders e clima
- (C) Grama mais verde e alta por uns dias depois da chuva; amarela na seca.
  - A seca já aumenta o fogo (`Clima.secura`); aqui só aparece na cor.
- (C) Flores por estação, que abrem de dia e fecham à noite.
- (C) Folhas caindo no outono, juntando no chão e levadas pelo vento (`Clima.vento_em`).
- (C) Juncos e algas balançando na margem; água parada ganhando limo com o tempo.
- (C) Depois de tempestade: galhos caídos, poças e cogumelos brotando (somem com o tempo).
- **Por que aqui:** é visual sobre sistemas que já existem e ainda não depende de bicho nenhum.
- **Já existia:** as poças nas baixadas, o chão molhado, a cor e a queda das folhas das árvores por estação, o junco
  balançando no vento e a vitória-régia boiando.
- **Feito:**
  - **Viço do capim:** `Clima.vico`, de −1 a +1. A chuva enche; sem chuva volta ao normal da estação em uns 2 dias
    de jogo, e o verão seco puxa para palha. O capim fica mais verde e alto ou amarelo e baixo, e também muda de
    cor pela estação.
  - **Flores:** 2 das 5 folhas de alguns tufos têm uma ponta colorida (branca, amarela, violeta ou rosa). Abrem de
    dia e fecham à noite; muitas na primavera, nenhuma no inverno.
  - **Folhas do outono:** caem girando das árvores caducas, levadas pelo vento, e ficam por cima do capim em volta
    da árvore. O orçamento é de 520, das árvores mais perto da câmera.
  - **Limo:** manchas grandes na água parada (o chunk marca lago na cor do vértice), juntando na beira. Mais forte
    no verão e some no inverno.
  - **Galhos:** caem embaixo das árvores quando passa uma tempestade (raios ou ventania; chuva comum não quebra
    galho), ficam uns dias e afundam no capim.
  - **Cogumelos:** brotam no pé das árvores com o chão molhado, fora do inverno; crescem, ficam um dia e murcham.
  - **Código:** `PlantasReagem` é a lógica, `DesenhoPlantasReagem` o 3D e `PlantasReagem2D` o 2D. A busca de
    árvores perto ficou no `Ecossistema` e serve às frutas da fase 3.

## Fase 3 — Frutas, arbustos e reflorestamento completo ⬜ · custo médio
- (S) **Frutas** caindo embaixo de árvores e **arbustos**. Elas viram fontes de comida no `Ecossistema` e
  apodrecem se ninguém comer.
- (S) Reflorestamento, por partes:
  - ✅ semente → muda (a semente vem dos pássaros);
  - ✅ a muda cresce até árvore (`AmbienteVivo.plantas`);
  - ⬜ jovem → adulta seguindo as estações reais;
  - ⬜ o chão morto (queimado, corroído, limpo) se recupera sozinho quando a causa some.
- (C) Chuva de sementes ao vento, na troca de estação.
- **Por que antes dos bichos:** é a comida deles. Rato e pássaro precisam de fruta para ter o que fazer.

## Fase 4 — Ciclo da morte ⬜ · custo médio
- (S) O animal morto fica no lugar: rato, pássaro, aranha e larva (pelo evento `morreu` da fase 0).
- (S) Ele apodrece em etapas (inteiro → inchado → ossos) e some.
- (S) **Moscas** pairando enquanto há carcaça. As moscas só existem onde há vida biológica morta (o mesmo efeito
  pequeno da fase 1).
- (C) A podridão deixa o chão mais fértil, onde as plantas brotam primeiro (liga com a fase 3).
- (C) Carcaça grande atrai carniceiros (os pássaros grandes; depois os predadores da fase 9).
- **Por que aqui:** usa a fundação e o reflorestamento, e as fases seguintes precisam dela (todo bicho novo morre
  e vira carcaça).

## Fase 5 — Ratos e pequenos animais ⬜ · custo médio/alto
- (S) Ratos: vivem no mato e nos arbustos, comem frutas e **enterram sementes** (reflorestam).
  - Fogem das larvas, do ácido e do fogo.
  - São presa das aranhas e das larvas.
- (C) Tocas com o bicho entrando e saindo.
- (C) **Pegadas e trilhas:** grama pisada onde os bichos passam muito (mapa de passagem do `Ecossistema`).
- (C) Olhos brilhando à noite passam a ser dos ratos de verdade.
- **Por que aqui:** precisa de comida (3), carcaça (4) e do índice (0).

## Fase 6 — Pássaros completos ⏳ · custo médio
- ✅ (S) 5 espécies, bandos em massa, fuga, sementes, noite e migração na lógica.
- ⬜ (S) Comem as frutas da fase 3 e morrem como os outros bichos (viram carcaça).
- ⬜ (C) Ninhos nas árvores.
- ⬜ (S) Migração visível: revoadas grandes na troca de estação; no inverno alguns tipos vão embora e outros chegam.
- ⬜ Conferir:
  - o desempenho no celular com até 90 pássaros;
  - o planador pousando;
  - a semente brotando, em vídeo.

## Fase 7 — A natureza reage à IA do jogador ⬜ · custo médio
- (C) A fauna se afasta do barulho e da poluição; em volta da fábrica fica quieto e cinza.
- (C) **Recuperação em etapas** quando a área é limpa: insetos → mato → ratos → pássaros → árvores.
  - Usa todas as fases anteriores, por isso vem depois delas.
- (C) Espécies que se adaptam à fábrica: ninho em torre velha, rato roendo cabo.
  - Roer cabo vira regra de jogo e mexe na energia.
  - Fica por último dentro da fase, com número baixo e liga/desliga no `fauna.json`.

## Fase 8 — Comportamento e guerra das espécies alienígenas ⬜ · custo alto · mexe no combate
- (S) Comportamento próprio por espécie, com um perfil `comportamento` no `inimigos.json`:
  - aranhas caçam em bando e abrem ninhos novos;
  - larvas ficam perto da cratera, cospem de longe e corroem.
- (S) **Procriação** por regra de cada espécie:
  - aranha pela poluição do ninho (como hoje);
  - larva pelo chão corroído e pela matéria morta (comem carcaças e árvore dissolvida).
- (S) **Guerra entre espécies.** Uma tabela `relacoes` (aranha × larva = hostil) diz quem ataca quem.
  - O território (teia no canal R e corrosão no canal G da `Infestacao`) empurra o do outro.
  - O vencedor cobre o chão do perdedor.
  - (C) O jogador pode usar isso: deixar duas espécies se desgastando, ou eliminar uma para a outra dominar.
- (S) Aliens caçam ratos e pássaros (presas das fases 5 e 6).
- **Por que por último entre os centrais:** é o que segura o combate do jogo. Mexer nele com o resto ainda mudando
  quebra o equilíbrio e os testes de ataque, que são muitos.

## Fase 9 — Fauna grande e eventos raros ⬜ · custo alto
- (C) Herbívoros grandes em manada, que migram e fogem de predadores e do fogo.
- (C) Predadores nativos que caçam ratos e herbívoros e brigam com aranhas e larvas (entram na tabela
  `relacoes` da fase 8).
- (C) Peixes que pulam nos lagos; na água poluída aparecem mortos boiando (viram carcaça da fase 4).
- (C) Enxames de insetos no verão úmido.

---

## Resumo da ordem
| Fase | O quê | Depende de | Custo | Mexe em regra de jogo? |
|---|---|---|---|---|
| 0 | Fundação (índice, eventos, orçamento) | — | baixo | não |
| 1 | Vagalumes, insetos, sons de ambiente | 0 | baixo | não |
| 2 | Plantas que reagem | — | baixo | não (só a cor da seca) |
| 3 | Frutas, arbustos, reflorestamento completo | 0 | médio | pouco (árvores voltam) |
| 4 | Carcaças, podridão, moscas | 0, 3 | médio | não |
| 5 | Ratos, tocas, trilhas | 0, 3, 4 | médio/alto | pouco (sementes) |
| 6 | Pássaros completos | 3, 4 | médio | não |
| 7 | Natureza reage à fábrica | 1–6 | médio | sim (cabo roído, opcional) |
| 8 | Aliens: comportamento, procriação, guerra | 0, 4, 5 | alto | sim (combate) |
| 9 | Fauna grande, peixes, enxames | 4, 8 | alto | sim |

Cada fase termina com os testes, o porte para o 2D, as baterias completas nos dois e o vídeo de conferência.
Antes de começar cada fase, mostro 1 ou 2 candidatas de arte e de som quando houver modelo ou som novo.
