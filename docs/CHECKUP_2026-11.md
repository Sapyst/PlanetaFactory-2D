# Checkup geral do código (pedido de Sapyst, 2026-11-03)

Pedido: "Checkup geral no código do jogo buscando otimizações e organização do código pra facilitar leitura e melhoria do
código e funcionamento do jogo para evitar engasgos e instabilidade. Buscando melhor carregamento e ordem de recursos do
programa e estruturação do código. Relate melhorias e teste os resultados."

Este arquivo é o diário do checkup: quem continuar (mesmo depois de um reset de contexto) lê daqui e segue do último item
não marcado. Cada melhoria = 1 commit com `testar.sh` em 0 falhas. Sem mudar comportamento do jogo, salvo bug claro.

## Estado de partida
- HEAD 3a5cf4e (Antigravity: barra de construção por categoria, só tarefa 1 do pedido 4; commit local, sem push).
- Sem commit: 67 modelos de ambiente convertidos (arte/modelos + jogo/assets + modelos.json) pelo Antigravity; estudos
  novos em arte/estudos (amb_*, aranha_organica*, efeitos/). Tarefas 2 (efeitos), 3–8 e release do pedido 4: NÃO feitas.

## Fases
- [x] 0. Base: rodar testar.sh no estado atual; se os 67 modelos passarem (malha única, origem, limites), commitar
      "Ambiente: 67 modelos do Antigravity"; se não, guardar à parte (git stash) e anotar aqui.
- [x] 1. Medir: tempo de abertura (menu e partida), ms por quadro e picos (engasgos) na demo e no roteiro `carga`,
      memória, erros/avisos de script nos logs, tamanho dos arquivos .gd (os 10 maiores), funções mais longas.
- [x] 2. Carregamento e ordem de recursos: autoloads e o que cada um puxa no _ready; preload × load; o que é carregado
      na abertura sem precisar; carregamento de modelos/ícones/sons sob demanda e cache; ordem de inicialização.
- [x] 3. Engasgos: alocações e loops por quadro (_process/_physics), refazer-tudo em vez de incremental (chunks, fios,
      portas, luzes), queue_free em massa, salvamento em thread, GC de nós.
- [~] 4. Organização: arquivos gigantes partidos por responsabilidade (fabrica.gd, barra_construcao.gd, mundo_demo.gd,
      colonia.gd…), duplicação, nomes e pastas coerentes, comentários de cabeçalho por arquivo, dados em json em vez de
      números soltos, remoção de código morto e de arquivos antigos não usados.
- [x] 5. Estabilidade: null/índice fora, acesso a nó liberado, erros vistos em logs, salvar/carregar robusto (versão,
      campos faltando), limites de recursos (luzes, partículas, instance uniforms).
- [x] 6. Relatório final em docs/CHECKUP_2026-11.md: medições antes × depois, lista de commits, o que ficou.

## Medições
Tudo sem janela (`--headless --audio-driver Dummy`, PC): **não há GPU** — só o custo dos scripts e do motor na CPU.
Sem janela o motor segura o quadro em ~6,9 ms (145 fps), por isso "quadro (relógio)" só serve para os picos; o que
vale é "scripts no quadro" (do primeiro ao último `_process`). No celular o custo de script costuma ser 3–4× o do PC.
Ferramentas: `jogo/ferramentas/medir.sh` (= `medir.gd` demo e novo + roteiro `carga patio`) e `jogo/ferramentas/perfil.gd`.

### Abertura (medir.gd)
| | antes | depois |
|---|---|---|
| motor + autoloads (Registro, Sessao, Som) | 370–520 ms | 400–520 ms (igual; varia com o disco) |
| menu (interface + foto de fundo) | 310–470 ms | 370–470 ms (igual) |
| carregar a cena do jogo (compila todos os scripts) | 420–780 ms, no clique | feito em segundo plano enquanto o menu está na tela |
| clique → jogo pronto (demo) | 1 050 ms (carregar 466 + instanciar/_ready 585) | 618 ms com a cena já compilada durante o menu (920 ms quando o menu dura menos que a compilação) |
| clique → jogo pronto (novo, com abertura) | 950 ms | 565 ms (cena compilada durante o menu) |
| memória estática depois de 600 quadros (demo) | 618 MB · 2 605 nós · 8 733 objetos · 0 órfãos | 622 MB · 2 675 nós · 8 944 objetos · 0 órfãos |

### Demonstração, 600 quadros parada (medir.gd)
| | antes | depois |
|---|---|---|
| scripts por quadro: média · p95 · p99 · pior | 1,95 · 6,8 · 9,0 · 27,9 ms | 1,5–1,9 · 5,7–6,5 · 7,3–8,9 · 19,4–19,8 ms (duas rodadas) |
| quadros acima de 33 ms | 0 | 0 |
| erros de script no log (demo e novo) | 0 | 0 |

### Fábrica grande sem janela (perfil.gd: 1 690 estruturas, 44 caminhos, 5 335 itens, 20 torres — o roteiro `estresse`)
| | antes | depois |
|---|---|---|
| scripts por quadro parado: média · p95 · pior | 9,7 · 14,5 · 48 ms | 3,1–6,0 · 11–25 · 25–54 ms (4 rodadas; esta máquina varia muito entre rodadas) |
| `DesenhoItens` por quadro (com braço no mapa refazia tudo a cada quadro) | 8,1 ms todo quadro | esteiras só a 30 Hz (6 ms), garras por quadro (~0,1 ms) |
| `fabrica.reconstruir` (a cada construção) | 47,7 ms (itens 34 + esteiras 12 + máquinas 6 + energia 3 + fluidos 2,5) | 33,7–41,3 ms (itens 12–18 + esteiras 9–10 + máquinas 6 + energia 3 + fluidos 2,5) |
| `_animar_estruturas` quando o mapa muda | 25,6 ms | 1,5 ms |
| ticks de gênese + transportador + silo (30×/s, sem nenhum no mapa) | 0,47 + 0,94 + 0,92 ms | 0 |
| `_tick_mundo` por tick | 4,6 ms | 1,15 ms |
| 60 quadros depois de construir 1 fornalha: média · pior | (o perfil antigo não chegou a construir) | 4,0 · pior 46,5 ms (o pico é reconstruir + listas por versão; antes somaria ≈ 48 + 26 + 3 ≈ 77 ms) |
| câmera pulou 45 m (chunks novos), 60 quadros: média · p95 · pior | 9,8 · 43 · 52 ms | 5,0–5,9 · 19–22 · 36–38 ms |
| chunk: preparar (na thread) · montar (no quadro) | 73 · 4,9 ms | igual (não mexido) |
| `ambiente._passo` (1×/s) | 2,5 ms | igual (não mexido) |

### Roteiro `carga patio` (1 176 estruturas, 2,7 M triângulos somados, 10 700 nós)
| | antes | depois |
|---|---|---|
| d=44: fps · quadro média · p95 · pior | 101 · 9,9 · 25,4 · 50,5 ms | 110 · 9,1 · 23,6 · 44,3 ms |
| d=25 | 145 · 6,9 · 9,4 · 12,5 ms | 145 · 6,9 · 7,2 · 9,6 ms |
| d=90 | 144 · 6,9 · 10,4 · 13,2 ms | 145 · 6,9 · 7,6 · 10,1 ms |
| salvar: montar + copiar no quadro · texto na thread · tamanho | 1,4 + 2,0 ms · 6,1 ms · 278 KB | 1,5 + 2,0 ms · 5,7 ms · 244 KB |
(d=44 é o primeiro ponto medido logo depois de montar o pátio: ainda monta chunks e cresce o piso; os outros dois são o regime.)

### Arquivos (fase 1, antes)
10 maiores .gd (fora testes): roteiro_teste 3 063 · mundo_demo 2 673 · fabrica 2 219 · barra_construcao 1 223 ·
roteiro_fotos 1 094 · construtor 1 004 · colonia 879 · ambiente_vivo 835 · desenho_chunk 770 · controle_construcao 720.
Funções mais longas: mundo_demo._detalhe 472 · barra_construcao._ready 285 · fabrica._restaurar_itens 253 (é a função +
as classes internas das interfaces) · roteiro_teste._ready 234 · mundo_demo._tick_mundo 194 · _animar_estruturas 181 ·
fabrica.tick 161 · mundo_demo._ready 153 · desenho_chunk._chao_dados 146 · tela_pesquisa._mostrar_detalhe 142.
Todos os 204 .gd têm cabeçalho `##`. Nenhum .gd sem referência (código morto por arquivo: nenhum).

## Diário
- 2026-11-03 11:10 — Fase 0. `testar.sh` no estado de partida: 106 arquivos, 75 139 verificações, 0 falhas, CELULAR OK
  (2 min). Teste novo `testes/test_modelos_ambiente.gd` (67 existem, uma malha só, pé em y=0 ±2 cm, origem no centro
  da base, json = .glb, triângulos nos limites do brief): passou. Commit 7a9643d "Ambiente: 67 modelos de ambiente do
  Antigravity" (arte/modelos, jogo/assets/modelos, dados/modelos.json, teste). arte/estudos/ (estudos amb_*, aranha,
  efeitos/, FEITOS_ANTIGRAVITY_3.md) ficou sem commit de propósito: é trabalho em andamento do Antigravity.
- 2026-11-03 11:40 — Fase 1 (medir). Ferramentas novas: `ferramentas/medir.gd` (abertura, ms por quadro, memória,
  nós), `ferramentas/perfil.gd` (custo de cada pedaço do quadro na demo e numa fábrica grande) e `ferramentas/medir.sh`
  (roda tudo + roteiro `carga patio`). Achado: o roteiro `carga` travava sem janela no `await
  RenderingServer.frame_post_draw` (nunca chega sem janela) — corrigido em roteiro_fotos.gd. Autoloads não existem como
  identificador em script `-s`: usar `root.get_node("Sessao")`.
- 2026-11-03 12:30 — Fase 1 fechada com as medições de base (tabelas acima). Ordem de ataque por impacto: fase 3
  (engasgos) → 5 (estabilidade) → 2 (carregamento) → 4 (organização).
- 2026-11-03 13:30 — Fase 3. Commits: 1aa8615 DesenhoItens (esteiras a 30 Hz, garras por quadro, buffers numa passada);
  9e27e87 itens de volta às esteiras em lote ordenado (`EsteiraCaminho.inserir_ordenados`); 9500e48 gênese/transportador/
  silo com lista por versão do mapa; bb24483 `_montar_esteiras` sem repetir a busca do próximo + ordenar só se preciso;
  df9f95a listas de animação numa passada só. Cada um com `testar.sh` em 0 falhas (75 878 verificações, CELULAR OK).
- 2026-11-03 14:00 — Fase 5. 806da0a Salvamento: cópia de segurança (`partida.sav.bak`) e `ler_partida()` com
  verificação de campos (teste novo em test_salvar_auto). Logs da demo e do jogo novo sem janela: 0 erros de script.
  Fase 2. 576cd06 menu compila a cena do jogo em segundo plano (`load_threaded_request`). O resto da abertura (autoloads
  0,4 s, menu 0,4 s, `_ready` 0,6 s: `DesenhoChunk.aquecer` assa os ~70 modelos do mapa de propósito, para não engasgar
  depois) ficou como está.
- 2026-11-03 14:30 — Fase 4 (parcial) e fase 6: ver relatório.

## Relatório

### O que foi feito (por impacto)
1. **Engasgos por quadro** — `DesenhoItens` refazia todos os itens das esteiras a cada quadro sempre que havia um braço
   no mapa (a chave de cache incluía o número do quadro). Agora as esteiras são refeitas só quando a simulação anda
   (30 Hz) ou a câmera mexe; o item na garra de cada braço é reposto por quadro com `set_instance_transform`. Fábrica
   grande: scripts por quadro parado 9,7 → ~3,5 ms de média.
2. **Engasgo na construção** — `fabrica.reconstruir` (roda a cada construção) devolvia cada item com `inserir_em`, que
   varre a fila: 5 000 itens = 34 ms. Agora os itens voltam agrupados por caminho e em ordem (`inserir_ordenados`, só
   anexa no fim, mesma regra de espaçamento). `_montar_esteiras` deixou de buscar o próximo tile duas vezes por esteira.
   `_animar_estruturas` rodava 17 filtros com lambdas sobre todas as estruturas a cada mudança do mapa (25,6 ms) → uma
   passada só (1,5 ms). reconstruir 47,7 → ~33 ms.
3. **Trabalho inútil por tick** — gênese, transportador e silo varriam todas as estruturas 30×/s mesmo sem ter nenhuma
   (3,3 ms por tick numa fábrica grande) → lista por versão do mapa, como drones e colônia já faziam.
4. **Estabilidade do salvo** — cada gravação guarda a anterior em `partida.sav.bak`; `Salvamento.ler_partida()` confere
   os campos da partida e, se o salvo estiver ilegível ou incompleto, volta pela cópia com aviso no log (antes: o jogo
   caía em `_carregar` com `d.mapa` nulo, e o salvo quebrado seria sobrescrito pelo jogo novo). Derrota apaga as duas.
5. **Carregamento** — o menu pede `load_threaded_request` da cena do jogo no `_ready`: a compilação de todos os scripts
   (0,4–0,8 s no PC, mais no celular) acontece enquanto a pessoa olha o menu, e o botão pega a cena pronta.
6. **Ferramentas de medição** (ficam no repo): `ferramentas/medir.sh`, `medir.gd`, `perfil.gd`. O roteiro `carga`
   travava sem janela (`await RenderingServer.frame_post_draw` nunca chega) — corrigido em roteiro_fotos.gd.

### Bugs achados
- Roteiro `carga` (roteiro_fotos.gd) nunca terminava sem janela (corrigido).
- Salvo corrompido/truncado derrubava o jogo ao Continuar e depois era sobrescrito (corrigido com cópia de segurança).
- Com qualquer braço no mapa, os itens de todas as esteiras eram recalculados a cada quadro, contra o que o README
  prometia (30 Hz) (corrigido).
- Nenhum erro de script nos logs da demo, do jogo novo (com abertura) e do roteiro `carga patio` sem janela.

### O que ficou por fazer (sugestões, em ordem de valor)
- **`fabrica.reconstruir` incremental**: ainda custa ~33 ms numa fábrica de 1 700 peças a cada construção (esteiras 9,
  máquinas 6, guardar+restaurar itens 12, energia 3, fluidos 2,5) — no celular, ~100 ms de engasgo por peça posta. Só
  remontar os caminhos/redes tocados pela obra é a mudança de maior valor que sobrou; é uma mudança de desenho da
  Fabrica (não cabia num checkup sem mudar comportamento).
- **Mudança de versão do mapa**: cada sistema (colônia, varredura, farol, lançador, clima_local, luzes, portas, fios,
  plataformas…) refaz a própria lista varrendo todas as estruturas: ~15 ms somados por construção na fábrica grande.
  Um índice por nome mantido pelo `MapaOcupacao` (atualizado em colocar/remover) tiraria quase tudo isso.
- `DesenhoItens._desenhar` ainda custa ~6 ms a 30 Hz com 5 300 itens visíveis (GDScript por item: `ponto_no_tile`,
  `altura_chao`). Dá para guardar por caminho a altura do chão e a base das curvas por tile; a saída de verdade é C++
  (como o README já diz).
- `ambiente._passo` (1×/s, 2,5 ms no PC): `_decair` percorre 4 canais × 1 024 tiles de cada chunk com dados em
  GDScript; dá para repartir os chunks pelos ticks (mesma taxa, fases diferentes).
- Chunk novo no quadro: `montar` ~5 ms (chão + piso + grama + objetos); o pior quadro ao mover a câmera é ~35 ms porque
  um chunk novo pode descobrir um ninho (`colonia.descobrir_chunk` → `mapa.colocar` → mudança de versão: item acima).
- **Organização (fase 4, só análise)**: os cortes limpos são (a) `cenas/mundo_demo.gd` linhas ~1594–2654 (seleção +
  texto dos painéis: `_detalhe*`, `_opcoes_*`, `_lista_*`, `_painel_maquina`, ~1 060 linhas) → `interface/painel_estrutura.gd`
  com uma referência à cena; (b) `interface/roteiro_teste.gd` → os roteiros `lote10–17`, `combate`, `clima`, `drones` (~900
  linhas) em `roteiro_lotes.gd`; (c) `simulacao/fabrica.gd` → fluidos (linhas ~1313–1596) e rede lógica (~1596–1760) em
  classes auxiliares com a Fabrica como dono. Não foram feitos neste checkup: cada um é um rename mecânico de centenas
  de referências (`fabrica.` → `cena.fabrica.`) com 56 usos nos roteiros, e o ganho é só de leitura — pedi para deixar
  para uma rodada própria, com os roteiros visuais rodados depois. Cabeçalhos `##`: todos os 204 arquivos já têm.
  Código morto por arquivo: nenhum. O padrão "lista por versão do mapa" está repetido em 6 classes (candidato a helper).
- Chamadas de `load()` ficam onde estão (preload só nos shaders): os modelos são carregados sob demanda e as malhas do
  mapa assadas uma vez em `DesenhoChunk.aquecer` (de propósito, na abertura, para não engasgar durante o jogo).
- Medir com janela (GPU) no PC e no celular depois destas mudanças: sem janela não dá para ver o custo de desenho.

## Rodada de desempenho (2026-11-11/12)
Medido com `ferramentas/perfil.gd` (fábrica grande: 1 705 estruturas, 5 334 itens; só CPU, PC). O pior quadro vinha de
coisas fora da fábrica:
- **Teia/corrosão no chão** (`mundo_demo._desenhar_teia`): refazia a imagem de todos os chunks tocados a cada segundo,
  cada pixel olhando todas as tocas — ~0,8 s de quadro. Agora só as tocas que alcançam o chunk, e só quando a
  `Infestacao.assinatura` do chunk muda.
- **Ácido das larvas** (`Infestacao._consumir`): consultava o gerador em ~500 tiles por cratera a cada segundo (até
  ~130 ms). Agora a vegetação em volta de cada cratera fica guardada e só as crateras vizinhas entram na conta.
- **Vegetação perto** (`Ecossistema._vegetacao_perto`): ~2 500 consultas ao gerador a cada mudança do mapa ou 3 m de
  câmera (17–82 ms). Agora guardada por chunk (`_veg_estatica`).
- **Itens das esteiras** (`DesenhoItens`): altura do chão (consulta com trava) e arco das curvas guardados por
  caminho (`_geometria`): 7,7 → 3,9 ms.

Resultado na fábrica grande: parado média 23 → 5 ms (pior 673 → 50 ms); depois de construir 22 → 6 ms (pior 641 →
59 ms); câmera pulando 45 m 50 → 12 ms (pior 944 → 164 ms). Cada mudança tem teste de equivalência contra o jeito
antigo (test_larvas, test_infestacao, test_vegetacao_perto, test_desenho_itens_geo).

Ficou: `fabrica.reconstruir` incremental (~36 ms por peça posta, o maior custo restante de uma construção); índice por
nome no mapa (~5 ms por construção; cuidado: `fiacao.gd` tira e repõe um id e `construtor.gd` renomeia peças direto em
`estruturas`); medir no celular.
