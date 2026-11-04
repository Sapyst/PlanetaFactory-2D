# PlanetaFactory — código do jogo (Godot 4.7)

Projeto Godot separado da arte. Toda regra numérica mora em `dados/*.json`; a arte (`../arte`) é copiada para
`assets/` por `ferramentas/sincronizar_arte.py`, que também gera `dados/modelos.json` (área, portas, partes).

## Rodar
```bash
godot --path jogo                       # abre a demo (mundo + mini-fábrica + aranhas)
jogo/ferramentas/testar.sh              # importa e roda todos os testes sem janela
jogo/ferramentas/testar.sh aranha       # só os testes cujo arquivo contém "aranha"
godot --headless --path jogo --quit-after 400          # roda a demo sem janela (pega erro de execução)
godot --path jogo --write-movie /tmp/q.png --fixed-fps 30 --quit-after 70 -- camera 13 -2 14   # foto
```
godot --path jogo --write-movie /tmp/r/q.png --fixed-fps 30 --quit-after 142 -- camera -3 2 11 roteiro construir   # teste visual com cliques injetados
godot --path jogo --write-movie /tmp/a/q.png --fixed-fps 30 --quit-after 200 -- roteiro ataque   # também: trem, poluicao, toque, painel
godot --headless --path jogo --fixed-fps 30 --quit-after 4000 -- acelerar 8 relatorio            # estado a cada 30 s de jogo
```

## Modos, salvar e progressão
- Menu inicial (`cenas/menu.tscn`): **Continuar**, **Novo jogo** (núcleo no spawn + kit inicial; construir custa itens do
  núcleo, remover devolve, limpar árvore/rocha rende material; pesquisa libera peças e receitas), **Demonstração**
  (fábrica pronta, tudo liberado, sem custo, não salva) e **Configurações** (volumes, tamanho da interface, sombras,
  orientação do estoque, autosalvar). Esc / botão Menu = pausa (salvar, carregar, configurações, sair).
- Salvo em `user://salvos/partida.sav` (texto; grava em .tmp e troca): a cada `autosalvar_s` (desligado, 1, 2, 5, 10, 15 ou 30 min; padrão 2; `nucleo/auto_salvar.gd`; os dados saem no quadro e o texto + disco vão para outra thread, com "Salvando…" na tela; nunca na demo nem na abertura; os testes gravam em `user://testes_salvos`), ao fechar e quando o Android
  manda o app para o fundo. Núcleo destruído = derrota (o salvo é apagado).
- Pesquisa (botão Pesquisa / T): laboratório com energia gasta pacotes de pesquisa (montadora: cristal lapidado +
  engrenagem). Árvore e custos em `dados/progressao.json`.

## Energia por fios
Só se põe postes; os fios aparecem sozinhos (`energia/fiacao.gd`): poste ↔ poste até 9 m (5 vizinhos mais perto),
poste ↔ gerador e máquina até 5 m da borda. Máquina já ligada não troca de poste; no painel dela: "aceitar 1/2/3
fontes". Remover um poste religa quem ficou sem. Fantasma do poste mostra os fios que vai criar e o anel de 9 m.
**Torre sem fio** (pesquisa "Energia sem fio"): liga torres até 40 m e máquinas até 14 m, feixe ciano em vez de cabo.
**Poste alto** (pesquisa "Transmissão longa", lote 13): cabo até 30 m entre postes altos (poste ↔ poste vale o menor
`raio_fio`: com o comum, 9 m), ligação de 3 m; `terminais` no pé das 4 cadeias de isoladores; arrastado, um a cada 20
tiles (`Construtor.PASSO_POSTE`). O anel do topo anima com `Fabrica.transmitindo(id)` (a rede dele entregando energia).

## Fontes, acumulador e opções das peças
- `energia/rede_energia.gd`: em cada rede as fontes **grátis** (núcleo, painel solar, turbina eólica) entram primeiro;
  o gerador só queima carvão para cobrir o que falta. Sobra carrega os **acumuladores** (até `acumula_kw`), falta
  descarrega. `estat` por rede: pode gerar, gera, demanda, consumo, carga (+ carregando / − descarregando), acumulado.
- Painel solar: `energia_kw × luz do dia × luz do clima` (nada à noite). Turbina: `energia_kw × (0,05 + 0,95 × vento)`.
- Lote 13: **painel solar 2** ("perda_nuvem" 0,15): `energia_kw × Fabrica.sol_limpo × (1 − 0,15 × Fabrica.encoberto)`
  (luz do dia; nuvem ou chuva, o maior). **Turbina de correnteza** ("renovavel": "rio", "no_rio", "flutua"):
  `MapaOcupacao.no_rio` (metade da área em tile RIO; motivo "fora_do_rio"), sem plataforma (`DesenhoPlataformas`),
  `energia_kw × Fabrica.rio` (`Clima.vazao_rio`: `vazao_rio` da estação + `chuva_vazao` × chuva). **Gerador a fluido**
  ("combustivel_fluido": fluido → MJ por unidade): `Fabrica._geradores_fluido` liga a boca de entrada na rede do cano e
  `_tick_geradores_fluido` enche `combustivel` (MJ) até `ESTOQUE_GERADOR_MJ`; queima como o gerador. Fluido novo
  `combustivel_seiva` (refinador). Anima queimando para a rede.
- Acumulador 2 e lote 14: **acumulador 2 / de cristal** são acumuladores comuns (`acumula_mj`, `acumula_kw`). **Turbina
  alta** ("altura_vento": 2): `VentoLocal.fator(t, dir, niveis_extra)` soma os níveis ao desnível do lugar, respeitando
  `alto_max`; nacele e hélice são partes do Animador, como na eólica (ventoinha e anemômetro: `rotor` e `antena`).
  **Reatores** ("combustivel_item": item → MJ, "estoque_mj"; `Fabrica.eh_reator`, destino `_NoReator`: só a tabela, por
  braço; a esteira não enfia item em construção). **Fusão** ("agua_por_mj", "tanque_agua"): `Fabrica.agua_reator` (vai no
  salvamento) enche do cano em `_tick_geradores_fluido`; sem água, `kw_de` = 0 e nada queima. **Núcleo de singularidade**:
  "inesgotavel" (fonte livre). Anima com `transmitindo` (reatores) ou ligado (singularidade).
- Peça no mapa guarda as opções: `desligada`, `modo` (`eco`/`normal`/`turbo` → `Fabrica.MODOS`: velocidade, energia,
  poluição) e `limite` do baú (fração de `capacidade_itens`). **Reparar** custa 1 placa de ferro por 25 de integridade.
- Ficha técnica (`BarraConstrucao.ficha`) no botão da peça; painel da peça mostra integridade, armazenamento, geração
  e a rede. Tabela completa: `docs/RECURSOS.md` (gerado de `dados/`).
- Acumulador: o cristal do meio acende com a carga e as bobinas soltam faíscas (`render/arcos_eletricos.gd`: fitas em
  cruz, sem virar para a câmera), mais ainda carregando ou descarregando. Cristais das máquinas brilham fraco só
  trabalhando (`instance uniform trabalho`, só na variante `material_pf_cristal.gdshader` para não gastar o buffer global com a fábrica inteira; comandado pelo `Animador`).

## Dia, noite e estações
- `Clima.hora` (0 = meia-noite) anda num ciclo de `dia_s` (720 s). `luz_dia()` rende o painel solar; `DesenhoClima`
  anda o sol de leste a oeste, deixa a luz alaranjada no fim da tarde e à noite troca para lua azulada (a troca
  acontece com as duas apagadas no horizonte); céu, ambiente e névoa escurecem para azul-noite. HUD mostra período e hora.
- **Estações pelo calendário real** (`tempo_real`): 7 dias reais cada (`estacao_s`), passam com o jogo fechado.
  Cada uma muda a duração do dia (`dia_extra`), a secura (fogo) e os pesos do clima.
- Fotos: roteiros param o relógio ao meio da manhã; `-- hora 0.0` fotografa à meia-noite; `-- ciclo` deixa andar.

## Luz à noite (render/desenho_luzes.gd, dados/luzes.json)
- `DesenhoLuzes` só lê a simulação. Uma fonte por estrutura (`maquinas` em luzes.json, no espaço do modelo): `fogo` âmbar tremendo, `cristal` violeta pulsando, `choque` em flash curto, `lampada` constante. Força por `forca_alvo`: máquina trabalhando 1; cristal parado com energia `ocioso_cristal`; sem energia ou desligada, 0. Gerador: queimando para a rede. Acumulador: pela carga. Para-raios e captador: só com chuva acima de 0,4.
- Hora: `fator_escuro(luz_dia, valores.luz)`. De dia não há luz nem brilho falso (as labaredas continuam).
- Luz real: conjunto de OmniLight3D sem sombra (`pc.luzes` 6, `celular.luzes` 3; cede lugar aos faróis acesos, mínimo 2), nas fontes mais perto de `Visao.centro`, troca em 0,6 s com folga para não trocar à toa. O resto vira halo no chão num MultiMesh aditivo (`luz_halo.gdshader`, `halos` por perfil), refeito 4×/s; o pulso roda no shader.
- Labaredas (`chamas` em luzes.json, `chama_lote.gdshader`, em lote, só no oval): a conversão (`EFEITO` em para_jogo.py) tirava fogo e faíscas dos modelos. Arcos: `ArcosEletricos.disparar`, até 5 por segundo no total. A fumaça de quem tem chaminé ou flare sai da ponta certa e ganha luz própria fraca à noite (`Fumaca.noite`).
- Cor da energia: `RedeEnergia.origem_de(id)`: em cada rede, quem entregou mais kW domina, sem mistura. `BASE` = núcleo e posto avançado (`Fiacao.eh_nucleo`); `GERADORES` = todo o resto, inclusive turbina, painel, reator, núcleo de singularidade e acumulador descarregando. Fontes livres entregam na proporção de cada uma. Histerese de 10% (`HISTERESE`), presa aos nós: sobrevive a `calcular` e, por `herdar_origem`, à rede refeita em obra. Sem energia passando: "".
- `RedeEnergia.fluxo_em(id)` (1×/s): tira as pontas que não puxam nem dão energia; ramal morto não acende. Só desenho, não muda nenhuma conta.
- Postes (`postes` em luzes.json): na cor da rede, força `0,3 + 0,7 × gera / gera_max`, só com fluxo. Cabos (`DesenhoFios`): faísca de 0,3–0,5 s num trecho de 25–45%, cabo com fluxo nas duas pontas, `faisca_por_cabo_s` e limite `faiscas` por perfil. Feixe da torre sem fio segue ciano.
- Noite (`DesenhoClima`): `LUA` 0,44, `AMBIENTE_NOITE` 0,62, `PREENCHE_NOITE` 0,85, 35% do ambiente em azul (`AZUL_NOITE`), céu igual. A lua entra logo depois da troca no horizonte (o entardecer era mais escuro que a meia-noite), e o fundo do céu escurece também.
- Roteiros: `-- modo demo roteiro noite [saida_fotos <pasta>]` (duas redes de verdade; noite, entardecer, dia, faísca) e `carga mostruario|patio noite [sem_luzes]` (tudo aceso, pior caso). Testes: test_luzes_noite.gd.

## Vento
- `Clima`: cada estação tem um rumo predominante (`vento_de` em `clima.json`); a direção do momento oscila ±40° em
  volta dele e vira devagar na troca de estação. **Rajadas**: frentes de vento mais forte (+18 a +43%) que nascem a
  barlavento de onde a câmera olha e atravessam o mapa (`vento_em(p)`); a grama e as árvores se curvam quando passam.
- Balanço da vegetação (`clima.gdshaderinc`, `material_pf.gdshaderinc`, `grama.gdshader`): força é amplitude, não velocidade. O relógio `vento_tempo` é somado aos poucos (`Clima.ritmo_vento`: no máximo +30% na ventania), nunca TIME × força, que parecia jogo acelerado e saltava de fase quando a força mudava. Vento forte: inclinação média a favor do vento + trancos (`vento_tranco`: frentes irregulares que andam com o vento, sobem rápido e voltam devagar), cada planta no seu tempo, com curva pela altura e teto; o topo desce ao inclinar, para não esticar a malha. Hélices de turbina continuam acelerando com o vento. Roteiro de comparação: `-- modo demo roteiro vento_cmp <pasta> <x> <z> <dist>`, com `--fixed-fps 30`.
  `vento_medio` = média móvel de 10 min de jogo (vai no save).
- `ambiente/vento_local.gd`: fator do lugar — alto +12% por nível acima do entorno (até +36%), baixada até −24%,
  campo aberto/praia/beira-mar +15%, floresta/pântano −30%, árvores plantadas −6% cada, a sotavento de construção
  alta e larga −20%. Números em `ambiente.json` "vento_local".
- Turbina: rende pelo vento do lugar dela (clima × lugar × rajada) numa curva — parada abaixo de 25%, sobe até 85%,
  plena até 115%, acima disso pás em bandeira (40%, protege). A nacele vira devagar para encarar o vento.
- Poluição do ar: o que vaza do chunk vai 70% vento abaixo (`vento_a_favor`), o resto para os 4 lados.
- Fogo já corria a favor do vento; chuva já caía inclinada; grama e árvores agora inclinam na direção do vento.
- Visão de recursos: V de novo liga a camada **Vento** — mapa de calor do vento médio de cada lugar, setas no chão
  na direção média e a ficha do tile com "vento médio aqui". Roteiros: `vento`, `turbina`.

## Árvores por receita
- `arte/blender_scripts/arvores.py`: cada espécie é uma receita (altura, tronco, galhos, forma e folha da copa) e cada
  uma das 6 variações sai de uma semente: carvalho, bétula, pinheiro, salgueiro, acácia e fungo-cristal (36 modelos,
  até 400 triângulos, cabem em 1 tile). Tronco e galhos existem de verdade embaixo da copa.
- No mapa os biomas sorteiam a espécie (`arv_carvalho`) e `Distribuicao.obstaculo` escolhe a variação pelo tile
  (`arv_carvalho_3`); `Distribuicao.especie()` volta para a espécie (rendimento, nome, madeira no fogo).
- Folhagem com material próprio (`P_Folha*`, mantido pela texturização) e perfil de estação no shader
  (`Materiais.PERFIL_FOLHA`, global `estacao_atual`): caducas amarelam/alaranjam no outono, perdem a folha e ficam
  nuas no inverno, brotam verde-claro na primavera; salgueiro amarela no inverno; acácia seca e perde metade no
  verão; pinheiro e fungo-cristal não mudam. Cada árvore muda no seu tempo (sorte por instância + onda pelo mapa).
- Balanço: inclinam para onde o vento sopra, mais na ventania e quando a rajada passa.
- Fogo em etapas: a copa queima primeiro (folhas somem), depois o tronco carboniza. Fogo curto deixa a árvore de pé,
  queimada (`MapaOcupacao.arvores`), que rebrota na primavera; fogo de 18 s ou mais derruba a árvore carbonizada
  vento abaixo (animação de 1,4 s; desvia de construção; se não houver saída, cai em cima e tira 40 de vida).
  Árvore queimada rende 2 carvões; tronco caído, 3. Roteiros: `arvores` (com `-- estacao E F`), `queimada`.

## Sujeira, consequências e limpeza
- `ambiente/ambiente_vivo.gd`: máquinas sujam o chão em volta, vazam óleo, despejam na água; enxurrada leva a sujeira
  para rios e lagos. **Consequências:** bomba de seiva com poça contaminada rende menos e se desgasta; chão sujo perto
  do ninho deixa as aranhas furiosas (nascem mais rápido, atacam em grupos menores, mais longe, mais fortes; olhos
  mais vermelhos).
- **Limpeza** (pesquisas Limpeza e Reflorestamento): coletor de lixo aspira sujeira e óleo num raio de 6; filtro de
  água (encostado na água) limpa a água suja; viveiro transforma seiva em mudas plantadas em volta (a 3+ tiles de
  construção), que crescem até árvore e limpam o chão e o ar.

## Chão de fábrica
Em volta de cada construção o chão vira piso de concreto (espalha 2 tiles, borda irregular e suave); zona de
minério nunca vira piso. Cristais, grama e seixos debaixo de construção (ou no piso) não aparecem.

## Esteira elevada
Botão **Nível** (N, PageUp/PageDown): chão, 0,5 m, 1,0 m. "Rampa sobe" sobe do nível atual (e o nível sobe junto);
"Rampa desce" desce. O traço elevado planeja pilares nos cantos da grade (aparecem no fantasma); passa por cima de
esteira/trilho (baixos) e não de máquina; nada alto pode ser construído debaixo depois. Remover leva os pilares junto.

## Fluidez (câmera)
Mapa gerado em segundo plano (WorkerThreadPool, até 3 chunks ao mesmo tempo, com cache por chunk na geração) e
montado 1 por quadro; pré-carrega 1 chunk além da vista e só descarrega a 2. Câmera desliza com inércia.
Medido arrastando a câmera 18 m/s (`-- modo demo roteiro panorama`): antes 71 quadros > 33 ms e picos de 95 ms;
depois 0 quadros > 33 ms. Celular: 3D a 70% da resolução, sem sombra, sem brilho; aranhas só desenhadas perto da
vista. Contador de FPS embutido (ligado por padrão na fase de testes; Configurações desliga).

## Interface (reforma 0.12)
- Pesquisa em tela própria (`interface/tela_pesquisa.gd`): a árvore de tecnologia inteira (`dados/arvore.json`, 166
  nós, gerado por `ferramentas/gerar_arvore.py` de `docs/ARVORE_TECNOLOGIA.mmd` + tabelas do `.md`) em três faixas de
  era (chapa com listras no título), colunas por pré-requisito dentro da era, linhas ligando (verde = feito). Nós são
  placas `Tema.botao_cor_estilo`; tipo no nó (■ estrutura, ⚗ receita, ▲ melhoria, ∞ infinita, ★ objetivo). Todas as
  166 estão em `progressao.json` desde o lote 11. Zoom: pinça, Ctrl + roda, gesto do trackpad, − e +.
- **Em desenvolvimento** (pedido de Sapyst; desde o lote 11 nada cai aqui, `testes/test_arvore_completa.gd` garante): `Pesquisa.em_desenvolvimento(id)` = fora do `progressao.json`, pacote que
  não existe (`Registro.itens`) ou pré-requisito em desenvolvimento (recursivo; já concluída não conta);
  `disponivel`/`escolher` recusam e `avancar` larga a ativa. `Pesquisa.peca_em_desenvolvimento(nome)` = sem modelo
  (`tem_modelo`) ou, fora da demonstração, nenhuma pesquisa que a libera dá para fazer. Visual único
  `Tema.botao_desenvolvimento` (placa `COR_DESENVOLVIMENTO` em todos os estados + `selo_desenvolvimento`: véu cinza
  escuro e etiqueta com moldura amarela, sem pegar toque): nó da árvore (`TelaPesquisa._botao_no`, ainda abre o
  detalhe, que diz o motivo com `motivo_desenvolvimento` e troca Pesquisar por "Em desenvolvimento"), peça da barra
  (`BarraConstrucao.botao_peca`, desligada; `marcar` não tira o cinza), `ControleConstrucao.escolher` avisa e não pega,
  `Construtor._cobrar_plano` marca o plano com o motivo `em_desenvolvimento` (vale também sem cobrança).
- Encardido: cada estrutura suja com o tempo (`AmbienteVivo.encardido`, 0..1; parada leva `encardido.cheio_s`,
  trabalhando e em chão sujo vai mais rápido) e a chuva lava (`chuva_limpa_s`), recomeçando o ciclo; vai no save. O
  valor vai no canal R do `fogo_mapa` e o `material_pf` cobre a estrutura de lama marrom (pé, frestas, escorridos) e
  pó claro (em cima), mais fosca. `-- roteiro encardido` fotografa limpa, meio suja e imunda.
- Melhorias: `bonus` na pesquisa (`progressao.json`), somado por `Pesquisa.bonus(chave)`; hoje lidos:
  `dano_torre_energia` e `dano_bala` (Colonia, tiro da torre) e `velocidade_pesquisa` (laboratório). `test_arvore`
  confere que toda chave de bônus tem quem a leia e que a árvore bate com as pesquisas jogáveis.
- Painel de detalhe como gaveta: do status até a borda de baixo, a lista rola dentro (nunca passa da tela). Em
  máquinas, cabeçalho com ícone, receita em casas (`interface/casa.gd`: número = o que tem; borda vermelha = falta),
  saída e barras de progresso e energia. Laboratório: botão "Abrir a pesquisa".
- Status do canto compacto (hora/clima, pesquisa); tocar abre tudo. Estoque do núcleo à parte (`interface/painel_recursos.gd`): casas de ícone + número, coluna (padrão, abaixo do status) ou linha, em Configurações; reparte em mais colunas se não couber, desvia da gaveta de detalhe e para antes das ferramentas e peças.
- Tamanho da interface (`config.texto`): 0,68 a 1,6, padrão 0,8 (o antigo mínimo). Config antiga exatamente no antigo padrão 1,0 desce para 0,8, uma vez (`ui_v2`); no celular segue o padrão de 1,35.
- Roda do mouse: o Godot deixa a roda atravessar os Controls (`mouse_force_pass_scroll_events`), e ela chegava ao mapa. `Toque.sobre_ui` procura qualquer Control que receba mouse na posição, em todos os CanvasLayer; sem registro por painel. Vale também para os gestos de trackpad. Roteiro: `-- modo demo roteiro roda_ui`.
- Modo construção: faixa listrada no alto dizendo o que a mão faz, com Sair; grade 1×1 no chão em volta do cursor.
- Estilo de fábrica (`interface/tema.gd`, texturas geradas por código): chapas grafite gastas com chanfro e rebites,
  filete de cobre, listras de perigo amarelo-sujo e preto na faixa e no Sair; paleta por situação (`Tema.COR`:
  destaque, perigo, sucesso, energia, pesquisa, água...) e por categoria (`Tema.CORES_CATEGORIA`, ícones tingidos).
- Ícones dos itens (`arte/icones/itens`, `icones.py -- itens`) para as casas.
- Torre de defesa básica liberada desde o começo: puxa 120 kW da rede até guardar 6 MJ, cada tiro gasta 0,05 MJ;
  munição vira reserva (pesquisa "Munição").

## Perfis de interface (PC × celular)
`Tema.pc` (`OS.has_feature("mobile"/"android")` ou `-- celular` = celular; o resto, PC). **Uma tabela só**: `Tema.MEDIDAS` (chave → [celular, PC]) e `Tema.ESTILO_*`; quem desenha pede `Tema.n/f/v/estilo`, nunca número nem `if` por painel. Coluna do celular = números de sempre: `ferramentas/testar.sh` roda `testes/conferir_celular.gd -- celular`, que monta a interface e compara cada controle com `testes/medidas_celular.json`, gravado antes da mudança.
No PC, 100% = a medida do perfil: 1 ponto = 1 pixel até janela de 1600×900, tela lógica de 1600×900 acima disso (`Sessao.fator_escala`). `ui_pc`: quem estava em até 80% (encolheu a interface grande de antes) volta a 100% uma vez.

## Portas no chão, fantasma e seleção
`MarcadorPortas` (MultiMesh + `render/shaders/marcador_porta.gdshader`: pulso e corte do oval no shader; viés de profundidade em vez de altura grande contra z-fighting) é o mesmo no aviso (`DesenhoPortas`, no lugar das placas Label3D) e no fantasma. `Portas.estados` é a regra única (`ok`); `soltas` é o filtro dela. Braço não atende porta de fluido (antes atendia, por engano). `Bloqueios` traduz o motivo do Construtor em texto curto e tiles. Bloqueado usa `fantasma_bloqueado.gdshader` (mistura; o aditivo não escurece). `DesenhoSelecao`: caixa de arestas numa malha só, sem tocar o material da peça.

## Painel, baú e braço
`BarraConstrucao.detalhe(titulo, texto, botoes, extra)`; `extra` e as chaves `secao`, `grupo`, `receita` só mudam a forma no perfil compacto. `Maquina.Estado.DESLIGADA`, `Fabrica._marcar_desligada`, `causa_maquina`, `Maquina.contar` (tempo e ritmo, no save). `Fabrica.copiar_config/colar_config` (`CAMPOS_CONFIG`). Baú: `e.aceita`, `e.aceita_limite`, `e.ordem`; `_NoBau` e `Fabrica.quanto_cabe` valem para braço e drones. Braço: `e.modo_braco = "radial"`, `Portas.origens_braco`, `Braco.origens` em rodízio, `Animador.giro_origem`. Faixa: `BarraConstrucao.lugar_faixa` (retângulos reais; pura e testada).

## Toque (celular primeiro)
- Toque × arrasto pelo dedo em milímetros reais (`interface/toque.gd`, 3,2 mm), não em pixels da tela de 720.
- Câmera: o chão fica preso embaixo do dedo (`CameraJogo.arrastar_tela`), sem atraso; pinça aproxima em volta do
  meio dos dedos (`zoom_em`); com o dedo na tela não há inércia, e soltar com o dedo parado não desliza.
- Listas (peças, painel de detalhe): `RolagemToque` rola arrastando em qualquer ponto (também sobre os botões), com
  embalo; o botão embaixo do dedo não é apertado se o toque virou arrasto (`RolagemToque.so_clique`).
- Pressionar e segurar 0,5 s = clique direito do mouse (larga traço, holograma e peça; vibra).
- Celular: interface 1,35× por padrão; tela estreita (< 1300 de largura lógica) põe as ferramentas só com ícone e
  estreita os painéis; a coluna de categorias cabe na altura. `-- roteiro telas celular` confere que nada passa da
  borda em 20:9, 16:9 e 4:3; `-- roteiro dedo celular [lista_cheia]` injeta toques e imprime o resultado.
- Categorias com ícones de símbolo em vetor (`assets/icones/categorias/*.svg`).

## Oval de visão, névoa e desempenho da grama
- `ambiente/visao.gd` (Visao): a tela vista como um oval deitado no chão, centrado no ponto olhado e do tamanho do
  zoom. Dentro, tudo desenha e anima; a borda é um degradê; fora, névoa escura (`aplicar_visao` em
  `clima.gdshaderinc`: chão, estruturas, vegetação). Fora do oval: objetos dos chunks escondidos (árvores, pedras,
  enfeites), grama some, Animador parado, fumaça das máquinas e chamas do fogo caladas, aranhas só na lógica, faíscas
  do acumulador paradas. A simulação continua igual — é só desenho.
- `ambiente/descoberta.gd`: o que já passou dentro do oval fica descoberto (células 2×2 tiles, no save); fora do oval,
  o descoberto aparece escuro e sem cor, o nunca visto quase preto — mascara a borda do mapa carregado.
- Grama em quadrantes de 16×16 m e duas camadas (`DesenhoChunk.ajustar_grama`): esparsa (1/3) até 40 m, detalhe
  (2/3) até 16 m com degradê; quadrante longe ou fora do oval não vai para a GPU. Medido (`-- roteiro medir`, câmera
  a 60 m, RTX): GPU 9,2 → 3,4 ms e 17,5 → 6,9 milhões de triângulos; densidade do celular 3,0 → 1,6 ms.
  `-- roteiro inventario` lista quem soma os triângulos.
- Árvores: cada chunk usa 3 das 6 variações de cada espécie (`Distribuicao.variacao_arvore`): 562 → 468 chamadas.
- Celular: sombra em 2 cascatas (em vez de 4) e até 60 m.
- Céu: só recebe cor nova quando a diferença se vê, e o reflexo é refeito aos poucos (Sky incremental).
- Sem música (só efeitos).

## Desempenho (medido: `testes/test_zdesempenho.gd` e `-- modo demo roteiro estresse`)
Sem janela (só CPU): `ferramentas/medir.sh [pasta]` roda `medir.gd` (abertura pelo menu, ms de script por quadro,
memória, nós; `-- novo` com a abertura) e o roteiro `carga patio`; `godot --headless --audio-driver Dummy --path jogo -s
res://ferramentas/perfil.gd` mede cada pedaço do quadro (reconstruir, chunk, itens, ticks…) na demo e numa fábrica de
1 700 peças, antes e depois de uma construção e de um pulo da câmera. Checkup de 2026-11: `docs/CHECKUP_2026-11.md`.
2 140 peças, 4 400 itens, 60 aranhas, 20 torres: passo de simulação ≈ 0,1 ms (fábrica) + 0,7 ms (aranhas/torres);
remontar a fábrica inteira ≈ 20 ms por construção. Desenho: esteiras/canos/trilhos em lote (MultiMesh por chunk:
~500 chamadas de desenho com 2 000 peças). O que mais pesa é posicionar os itens das esteiras (GDScript): até
~10 ms com 8 000 itens na tela — por isso só redesenha a 30 Hz, recorta o que está fora da tela e esconde os itens
com o zoom acima de 50 m. Se precisar de mais, é essa parte (não a simulação) que vale passar para C++.

## Android
`godot --headless --path jogo --export-debug "Android" jogo/export/PlanetaFactory-0.2.0.apk` (arm64, Vulkan Mobile,
paisagem, assinado com a chave de depuração em ~/.local/share/archivys_keys). Testado no emulador (x86_64, versão de
teste com OpenGL; o Vulkan do emulador sem janela não apresenta quadros): menu, jogo novo e construir com o dedo ok.

## Som
`ferramentas/gerar_sons.py` sintetiza os efeitos (assets/sons; precisa de numpy e scipy). Cada som é feito em camadas
(transiente, corpo e cauda), com metal batido por ruído em ressonâncias amortecidas, granulado para terra e chapa
amassando, reverberação curta e volume calibrado; o peso fica entre 150 Hz e 6 kHz, para soar no celular.
`nucleo/som.gd` toca:
- pontual, posicionado no mundo, com intervalo mínimo e limite de vozes por som;
- variações: `nome__2.wav`, `__3`… são sorteadas a cada toque (o passo da aranha tem 4);
- máquinas, esteira e trens em laço contínuo (`loop_maquina`), renovado pelo mundo a cada 0,35 s: entra e sai com
  fade, começa num ponto ao acaso do laço; só as 6 máquinas mais perto da câmera tocam.

## Fábrica do jogador
Tudo que se constrói funciona — a mini-fábrica da demo é só um mapa pronto rodando na mesma `Fabrica`.
- Esteira entrega na porta de entrada da máquina em que termina; esteira que termina na lateral de outra entra nela.
- Saída de máquina (porta) põe na esteira em frente. Braço: pega atrás, solta na frente, só pega o que o destino aceita.
- Logística da era base (fase 2.2b): **Esteira rápida** (`logistica_3`): as mesmas peças com `"classe": 2` na estrutura
  (`Construtor.CLASSES_ESTEIRA`; modelos `<peça>_rapida`, faixa vermelha; regra própria em estruturas.json), 3,75 m/s,
  passagem até 6 tiles livres (só liga entrada e saída da mesma classe). Trocar de classe no meio da linha parte o
  caminho em dois, ligados pela ponta (`elos` em `Fabrica._montar_esteiras`); traçar uma classe por cima da outra
  troca a peça (devolve o custo da velha, cobra a nova). Todo braço escolhe no painel (grade de ícones) **1 item** ou Auto (`Fabrica.escolher_filtro`, campo `filtros` da estrutura, vai no save); **Braço com filtro**: até 5 itens (`filtro_max`). **Divisor com filtro**: `filtro_item` sai só pela
  `saida_filtro`; o resto tenta a `prioridade` primeiro (Frente/Direita/Esquerda no painel; sem = rodízio).
  **Silo de granel** 3×3: armazém de 20.000 de um tipo só (`um_tipo`). **Cano subterrâneo**: a entrada liga na
  primeira saída alinhada à frente, mesma rotação, até 9 tiles livres — uma rede de fluido só.
- Água e química (fase 2.3): fluidos em `dados/fluidos.json` (`agua`, `agua_limpa` — serve onde se pede água —,
  `seiva`; `Registro.fluido_serve`). **Bomba d'água** 2×2 (`tomada_agua`: água encostada no lado sul do modelo,
  `MapaOcupacao.tiles_da_tomada`; água suja na tomada rende menos), **coletor de chuva** e **condensador de neblina**
  (`Fabrica.chuva`/`neblina` vêm do clima → `Maquina.clima`; 0 = `ESPERANDO_CLIMA`; `tanque_fluido` = tanque interno),
  **filtro** com `transborda` (solta água limpa com a pesquisa; sem cano não trava), **supressor de incêndio**
  (`AmbienteVivo._supressores`: apaga o fogo no raio e protege a vegetação; `Fabrica.jatos` → jato em `Efeitos`).
  Receitas refrigeradas (+50%), resina, pacote químico e ecológico no refinador; saída de fluido de receita que não
  solta fluido vira 2ª entrada (resina: seiva numa boca, água na outra). Sem janela: `-- roteiro agua`.
- Combate do meio (fase 2.4, `Colonia`): torre de munição genérica pela regra (`municao_item`, `tiros_por_item`,
  `municao_max`; `Colonia.item_municao/tiros_por_item`, o braço só entrega o item certo). Torre de projétil
  (`projetil`: velocidade, raio) solta um tiro que voa (`Colonia.projeteis`) e explode em área no ponto mirado
  (evento `explosao`; metade do dano na borda); `alvo: "ninhos"` + `alcance_min` na artilharia; melhorias pela regra
  (`bonus_dano`, `bonus_cadencia`, `bonus_alcance`). **Mina de pulso** (`pulso`: gatilho, raio, atordoa, rearme →
  `aranha.atordoada`, `Colonia.minas`). **Gerador de escudo** (`escudo`: raio, mj_por_dano): usa a mesma carga da
  rede da torre de energia (`carga_mj` → `Fabrica.carga_torre`); `_morder` pergunta `_escudo_absorve` antes de tirar
  vida. **Muro de campo** (`regenera` × `Fabrica.energia(id)`, satisfação da rede). Desenho: foguete/granada voando em
  arco com rastro, explosão, anel do pulso, bolha (shader `render/shaders/campo_escudo`, a parede do muro de campo
  usa `campo_parede`), selo/estojo ejetado maior ("capsula" em modelos.json) e `Animador.boca()`. Sem janela:
  `-- modo demo roteiro combate`.
- Clima (fase 2.5): **raios** (`ambiente/raios.gd`, `Raios`): o evento "raio" do `Clima` (`raios_por_s` do estado)
  vira um ponto do mapa (a até `raio_sorteio` m de uma construção sorteada por altura²); regulador (`ClimaLocal.sem_raio`)
  cancela, cúpula pega, para-raios/captador (`capta_raio`: raio, mj, prioridade) pegam o mais perto; sem proteção, a
  construção mais alta a `busca` m leva `dano` (`Colonia._escudo_absorve` antes) e acende fogo (`AmbienteVivo._acender`)
  / marca o chão queimado. A energia entra nos acumuladores da rede da peça (`Fabrica.injetar`; para-raios e captador
  têm papel "fonte" na `Fiacao`). Captador: `Maquina.ciclo_agora()` (receita `carregar_cristal`, `por_raio`; anima
  `capta_raio.anima_s` depois). Contador `Raios.descargas` (salvo). Desenho: `DesenhoClima` desenha cada `Raios.quedas`
  no lugar (ponta do para-raios, topo da construção; na cúpula, campo + arco até o cristal), clarão e trovão pela
  distância. **Máquinas de clima** (`ambiente/clima_local.gd`, `ClimaLocal`; regra `clima_local`: tipo, raio): zonas só
  com energia; `chuva_em` (coletor: `Fabrica.chuva_maq`; fogo do `AmbienteVivo`), `vento_em` (turbina, fogo, desenho
  da turbina; poluição: `Poluicao.vento_chunks`), `sem_tufao`, `sem_raio`. `DesenhoClimaLocal`: cúpula de campo
  (shader `campo_escudo`, acende ao pegar raio) e chuva em anel só no círculo do semeador. Escudo 2: bônus
  `escudo_raio`, `escudo_carga`, `escudo_recarga` (`Colonia.raio_escudo`, `Fabrica.carga_max`, `kw_de`). Sem janela:
  `-- modo demo roteiro clima`.
- Drones (fase 2.6): `drones/drones.gd` (`Drones`, lógica pura) e `drones/desenho_drones.gd` (`DesenhoDrones`). A
  estação (`estacao_drones`, regra `drones` em estruturas.json) é máquina: receita `fabricar_drone`; o drone pronto fica
  em `Maquina.saidas` (`Maquina.retem`: braço não tira) e `Drones._montar` põe na frota (até `frota_max`). Tipo por
  estação em `drones_tipo` na estrutura (reparo, combate, logistico). Estados `Drones.E` (HANGAR, NASCENDO, DECOLANDO,
  INDO, TRABALHANDO, VOLTANDO, POUSANDO, CAINDO); bateria (`voo_s`, volta com folga), recarga no hangar com a energia da
  estação; raios (`raios_agora`) seguram no hangar sem `drones_tempestade`. Reparo: `Colonia.vida` + placas do núcleo
  (`pago`: ♥ já pagos); combate: `Colonia.ferir_aranha`, mordida das aranhas perto; logística: papel do baú em
  `logistica` (provedor/requisitante, `pede_item`, `pede_qtd`), viagens reservadas pelo que já está a caminho. Melhorias
  pelos bônus `drones_*`; o tipo logístico pela pesquisa `drones_logisticos` ("modos"). Desenho: modelos
  `drone_reparo/defesa/logistico` (rotor0..3, giro/ombro/cotovelo, torre/canhao/boca, pendulo/carga), atitude por
  mola-amortecedor, holograma (shader `render/shaders/holograma`), scan (`scan_reparo` como `material_overlay` na
  estrutura + folha e leque em fita), traçante + cápsula (`DesenhoColonia.ejetar_capsula`), sucata fumegando. Sem janela:
  `-- modo demo roteiro drones`.
- Limpeza nova (fase 2.6, `AmbienteVivo._limpeza`): regra `limpa` com `queimado` (cinza) e `residuo` (o que
  `_limpar` tira vira item resíduo, `_compactar`); `purifica` (`Poluicao.absorver` no chunk; `residuo_por`); `planta`
  com `cresce` e `especie_bioma` (`AmbienteVivo.especies`/`rapidas`, `especie_do_bioma`; `DesenhoPlantas` usa os modelos
  da espécie); `restaura` (semeador de bioma: queimado, `mapa.arvores` de volta, mudas do bioma). Biodigestor (receita
  `biodigerir`) e estação de tratamento (`tomada_agua`, `limpa.agua`, `tratar_agua` com `transborda`). Recuperação de
  solo: o tile aplainado passa por `AmbienteVivo.recuperar` (mundo_demo.sincronizar). Sem janela: `-- modo demo roteiro
  limpeza2`.
- Abertura (fase 2.6): `cenas/abertura.gd` desce a cápsula `nucleo_queda` (conv_nucleo.py, animação "chegada" de
  240 quadros) e toca a chegada do impacto em diante; no fim troca pelo núcleo do jogo. Sem janela: `--fixed-fps 30
  -- novo roteiro chegada abertura`.
- Fim da fase 2: **Esteira expressa / quântica** (`logistica_4` / `logistica_5`): classes 3 e 4 em
  `Construtor.CLASSES_ESTEIRA` (modelos `<peça>_expressa` / `<peça>_quantica`, conv_esteiras_niveis.py; lonas
  P_EsteiraExpressa e P_EsteiraQuantica em `Materiais.ROLAGEM`), 5,625 e 7,5 m/s, passagem até 8 e 10 tiles livres.
  `EsteiraCaminho` guarda a sobra do tick: na entrada o item entra colado no anterior (fila contínua) e na saída, com a
  fila toda encostada, o próximo sai no mesmo tick — a 30 quadros/s a expressa entrega 3× (antes, 2×).
  **Trem-tanque** (`vagao_tanque`, peça `trem_tanque` = `Trem.COMPOSICOES`): `Trem.fluido`/`fluido_qtd`/`origem_fluido`,
  25.000 por vagão-tanque; `Trem.trocar_fluido` troca com `estoque.fluido` = {modo, f, qtd} da estação. A `Fabrica`
  liga à rede o cano com a boca virada para um tile da estação (`_estacoes_fluido`) e move 1.000/s (`vazao_fluido`)
  entre a rede e o tanque da estação (`tanque_fluido` 25.000) conforme o modo do painel (desligado/carregar/
  descarregar). **Braço empilhador** (`braco_empilhador`, conv_bracos_novos.py): `Braco.pilha_max` = regra `pilha`
  (4): pega na origem os iguais que já estão lá e solta um por vez (`Braco.qtd`, salvo).
- Lote 16 (trilhos, drones e lógica; arte/estudos/conv_lote16.py): **sinal em cadeia** (`GrafoTrilhos.cadeia`;
  `Trem._trecho_cadeia` reserva tudo ou nada os blocos até o próximo sinal comum e o bloco depois dele) e **rotas com
  condição** (`Trem.condicoes` por estação: "tempo"/"cheio"/"vazio"; `Trem.retroca` pede ao mundo outra troca de carga a
  cada 1 s; `Pesquisa.modo_liberado("trem_condicao")`). **Bomba de estação** (`bomba_estacao`): `_estacoes_fluido`
  agora vem dela (costas na estação, boca no cano), vazão × energia, `Fabrica.bomba_ativa` anima. **Trilho
  energizado** (`GrafoTrilhos.RETOS`; `Fabrica._trechos`, `energia_trilho`, `pedir_trilho`) e **trem elétrico**
  (`Trem.COMPOSICOES.trem_eletrico`, `Trem.energizar` põe `vel_max` 12 ou `VEL_BATERIA`; tração no dobro); a diesel
  emite `Trem.POLUICAO_DIESEL`. **Rede lógica** (grupo "logica"): `Fabrica.canais`, `valor_sensor`, `logica_off` (entra em
  `ligada`), `_tick_sensores` (por `EsteiraCaminho.a_frente`/`saidos`), `_tick_valvulas`; o painel em
  `_opcoes_logica`. **Baú de estoque**: `Drones.papel` = "estoque", `_mais_perto_com`, `estoque_livre`. **Braço
  quântico**: `Fabrica.alcance_origem` (campo "alcance" 1..`alcance_max`), `Animador._lanca_quantica` e o caminho do
  item no campo (`ponto_garra`). Roteiro sem janela: `godot --headless --path jogo --quit-after 900 -- modo demo
  roteiro lote16`. Lote 17 (proliferação: sensor, farol, posto, lançador, receptor, transportador, silo):
  `godot --headless --path jogo --fixed-fps 30 --quit-after 400 -- modo demo roteiro lote17`. Lotes 13 e 10 (energia I e
  produção I: poste alto, turbina de correnteza, gerador a fluido, painel solar 2, montadora 2, refinador 2):
  `godot --headless --path jogo --quit-after 200 -- modo demo roteiro lote13`. Acumulador 2 e lote 14 (energia II):
  `godot --headless --path jogo --quit-after 400 -- modo demo roteiro lote14`.
- **Montadora 2 / Refinador 2** (lote 10): máquinas de receita com "maquina" igual à da 1 (mesmas receitas),
  velocidade 1,0 / 2,0 e "encaixes_modulo" 2 / 3 (só mostrados no painel: os módulos não existem). O refinador 2 tem
  uma 2ª entrada de fluido (S1) e suja o mesmo por minuto (metade por produto).
- **Fornalha de aço / Fornalha elétrica / Broca grande / Laboratório 2** (lote 10): "maquina" `fornalha` em duas (a escolha
  da receita pelo que chega olha "maquina", não o nome; `combustivel` só na de aço, cujo fogo é o mesmo `FOGO_KW`; a
  elétrica é consumidora comum, sem `poluicao`, fora de `despejo` e `maquinas_quentes` em ambiente.json); `broca_grande` na
  lista `DESPEJA_NA_ESTEIRA` e com "maquina" `broca` (jazida, produtividade); `laboratorio_2` entra em
  `Fabrica.laboratorios` pelo grupo e conta `velocidade` da regra em `lab.t` (o Animador toca enquanto
  `Fabrica.lab_trabalhando`; o laboratório 1 segue como era). `-- modo demo roteiro lote10` (use `--fixed-fps 30`).
- **Módulos, linhas e o fim da árvore** (lote 11): módulos ficam em `modulos` na estrutura (vão no save; `Fabrica.por_modulo`,
  `tirar_modulo`, `aceita_modulo`, `encaixes`), efeito em `_recalcular_efeitos` (próprios + irradiadores com energia, refeito por
  `_aplicar_melhorias` quando muda obra, módulo, pesquisa ou energia dos irradiadores), aplicado em `Maquina.velocidade`/`produtividade`,
  `kw_de`, `_emitir` e no tick do laboratório. Item de módulo: campo `modulo` em itens.json. `Fabrica.linha2[id]` é a 2ª `Maquina`
  da montadora quântica (regra `linhas`), com `escolher_receita(id, r, 2)`, `trabalhando(id)` e save em `linha2`; `_NaMaquina` entrega
  a quem aceita. Receita com `so_em` só sai nessas estruturas (`Registro.receita_cabe`). Máquina `forja` nova; a fundição é `fornalha`
  (`_receita_para` prefere a exclusiva). `Maquina.rende_esgotada` (broca de núcleo): ninguém põe `jazida_restante`, as jazidas não se
  esgotam. Munição especial: `municao_especial` na regra da torre, `Colonia.carregar_especial`, `torres[id].especial`, `especial_da_vez`;
  `Colonia.artilharia_auto`, `ordenar_disparo`, `harmonia`, `ninhos_paz`; `Poluicao.fator`; `Trem.fator_vel`; `Fabrica._ligar_colonias`.
  `-- modo demo roteiro lote11` (use `--fixed-fps 30`).
- **Sensor de varredura** (lote 17; `ambiente/varredura.gd`, regra "varredura" em `estruturas.json`): consumidor de
  150 kW; `Varredura.tick` revela, por sensor, o próximo chunk de `ordem(id)` (mais perto do centro primeiro) a cada
  `intervalo_s` × energia, até `chunks` (6) ou `chunks_profunda` (16, modo `varredura_profunda` da pesquisa
  `cartografia`); chunk já todo visto entra na hora. Revelar = `Descoberta.marcar_chunk` + `Colonia.descobrir_chunk`.
  `ninhos_marcados()` (ninhos em chunks de sensores de pé), `jazidas(id)` (profunda: manchas com centro nos chunks,
  total somado dos tiles e nível pobre/média/rica), `estado()`/`restaurar()` no save ("varredura"). Desenho:
  `render/desenho_varredura.gd` (alfinete "⚠ Ninho" e rótulos das jazidas, sempre por cima). Painel:
  `mundo_demo._detalhe_varredura`. Anima (laço do estudo: giro + antena) com energia, no ritmo dela.
- **Farol de cristal** (lote 17; `ambiente/farol.gd`, regra "farol"): consumidor de 30 kW; aceso = energia > 0 e
  `Clima.luz_dia() < acende_abaixo` (0,35). Aceso, `Descoberta.marcar_circulo(centro, raio)` (10 m) e as aranhas em
  `Colonia.aranhas` dentro do raio são vistas: aranha nova dá o evento "aranhas_no_farol" (no máximo 1 a cada
  `aviso_s` por farol; o mundo avisa com o rumo). `render/desenho_farol.gd`: até 8 OmniLight3D âmbar (os faróis acesos
  mais perto do centro da vista), força `Farol.forca` (escuro × energia). Anima (carrossel) aceso.
- **Posto avançado** (lote 17; regra "posto"): núcleo-filho — grupo poste, `sem_fio`, `inesgotavel`, −150 kW
  (`Fiacao.eh_nucleo`: liga máquinas sem cabo, poste por cabo, como o núcleo); estoque próprio em `Fabrica.baus`
  (`Fabrica.eh_posto`; 3.200; braço e drones logísticos — papel "estoque"); `Fabrica.posto_que_cobre(tile)` (mais perto
  a até `raio_obra` 32 m) e `Construtor.estoque_local`/`estoque_do_posto`: a obra paga primeiro com o estoque do posto
  (`_pagar`; `rel.locais` para o desfazer devolver ao posto; saiu → núcleo). Pesquisa jogável desde o poste alto
  (`transmissao`, lote 13).
- **Lançador de sementes** (lote 17; `ambiente/lancador.gd`, regra "lancador"; item `nucleo_semente`, receita na
  montadora): `Fabrica._NoLancador` põe a semente em `sementes` na estrutura; alvo `alvo_rumo` (0–7) e `alvo_dist`
  (60–400 m) na estrutura (`Lancador.mirar`, painel). Com semente, alvo com pouso (`lugar_de_pouso`: 3×3 seco, plano,
  livre, até `procura` tiles; cache por versão do mapa) e energia, carrega `carga_s` × energia; o disparo toca o laço
  do estudo do começo (`Animador.reiniciar`) e a cápsula sai em `disparo_s`; `voos` em arco (`posicao_no_voo`) a 40
  m/s; no pouso limpa obstáculos, `mapa.colocar` do posto avançado, `Fiacao.ligar_novo`, chunk revelado e evento
  "semente_pousou" com o relatório para `mundo.sincronizar`. Parado (sem semente/alvo) puxa 5% (`Fabrica.fator_kw`).
  Save: "lancador" (voos e carga). `render/desenho_lancador.gd`: cápsulas no ar e anel do alvo.
- **Colônias e receptor de cápsulas** (lote 17; `ambiente/genese.gd`; pesquisa `colonias`, modo "colonias"): com o
  modo, o posto que nasce de uma semente ganha `colonia` e o `kit` (`kit_inicial` → `Fabrica.baus` no reconstruir).
  `Genese.tick`: cada colônia faz 1 `pacote_genese` a cada `genese_s` (30 s; sem receita) e manda em cápsula ao
  receptor com energia e lugar mais perto (`receptor_para`, conta as no ar); sem receptor, espera no estoque da
  colônia (até `guarda`). Chegada: `recebido` na estrutura do receptor (`Fabrica.campo`; `origem_em` → braço) e o laço
  toca uma vez. Save: "genese" (voos).
- **Transportador quântico** (lote 17; `ambiente/transportador.gd`, regra "transportador"): `entrada` (braço põe,
  20) e `saida` (braço tira, 200) na estrutura; com energia manda `taxa` (5) itens/s × energia para outro do mesmo
  `canal` (A–D, painel) com lugar, em rodízio.
- **Silo de lançamento** (lote 17; `ambiente/silo.gd` `SiloLancamento`, regra "silo"): `Fabrica._NoSilo` aceita só o
  que `parte`/`carga` pedem (até `guarda` ×) em `silo_itens`; o propelente vem do cano da boca leste (`Fabrica._tick_silos_fluido`, tanque 500; `abastecer` faz o mesmo em código). Com energia monta 1 parte em `parte_s` × energia até 100, depois a carga (modo
  `carga_semente` da pesquisa `foguete_proliferacao`); `lancar` (painel) → `lancamento_s` de subida e
  "foguete_lancado" → `MenuPausa.abrir(false, true)` (tela de vitória; não no roteiro). Estado na estrutura
  (`partes`, `carga`, `silo_t`, `lancados`). `render/desenho_silo.gd`: foguete crescendo com as partes, ogiva com a
  carga, subida com chama e luz.
- Extrator/broca mineram a jazida de baixo; fornalha escolhe a receita pelo que chega e queima carvão/biomassa;
  montadora/refinador: receita escolhida no painel. Elétricos precisam de poste (cobertura 2,5) ligado a gerador com combustível.
- Torre: cada munição que chega (braço ou esteira na porta sul) = 10 tiros. Quem trabalha polui (e vira alvo por 60 s).
- **Clique/toque com a mão vazia** numa peça abre o painel: estado, conteúdo, combustível, munição, receitas.
  Num trem: carga e **rota** (liga/desliga estações na ordem; sem nenhuma, passa por todas).

## Trem, poluição e aranhas
- **Trem**: aba Trilhos → Trem, em cima de um trilho reto. Roda por todas as estações da malha em ordem; carrega o que
  braços deixaram na plataforma ("para enviar") e descarrega na estação seguinte ("recebido"). Sinal ao lado da linha
  divide blocos (1 trem por bloco). Numa volta, todos rodam no mesmo sentido; em linha com fim de linha, vai e vem.
  Trens que se encaram destravam: depois de 8–17 s esperando, um deles tenta a rota pelo outro lado.
- **Poluição**: máquinas emitem no chunk; a nuvem vaza para os vizinhos e o chão absorve (floresta muito, deserto pouco).
- **Ninhos** nascem longe do spawn (≥ 52 tiles), absorvem a poluição que chega e a transformam em aranhas. Juntou 4,
  o grupo ataca a fonte de poluição mais perto. Muro e máquina no caminho são mordidos; esteira e trilho ficam por baixo.
  De tempos em tempos as aranhas constroem um ninho novo (14–30 tiles do antigo, 26+ de qualquer estrutura).
- **Torre**: 18 m de alcance, 3 tiros/s, vem com 60 de munição e recebe mais pela Fabrica. Aranha primeiro, depois ninho.
- **Metralhadora** (pesquisa "Metralhadora": defesa + aço): 2×2, só bala — 10 tiros/s, 3 de dano, 18 m; começa vazia e
  guarda até 200 tiros (o braço não entrega na cheia). Melhorias `dano_bala` (dano 1 e 2) e `cadencia_bala` (cadência 1).
  O tambor de 6 canos gira na rajada e todo tiro (das duas torres) ejeta uma cápsula com fumacinha pela calha do modelo.
- **Muro de tijolo** (pesquisa "Muro de tijolo"): 700 ♥, o dobro do muro de pedra; custa 5 tijolos; arrasta em linha.
- Expansão só sai de ninho que absorveu poluição. Aranha que não se aproxima do destino por 15 s desiste.
- Ritmo medido na demo (`-- acelerar 8 relatorio`): ataques a cada ~6 min; torres seguram o grupo.

## Câmera
Entre isométrica e de cima: inclinação de 56° (zoom perto) a 74° (zoom longe), lente de 38°. Começa a 44 m;
zoom de 8 a 150 m. De longe carrega mais chunks (até 11×11), a névoa afina e os enfeites miúdos somem.

## Construir (PC e toque)
| | PC | Toque |
|---|---|---|
| Escolher peça | barra de baixo, ou 1..9 na aba aberta (Tab troca de aba) | tocar no botão |
| Pôr | clicar (o fantasma segue o mouse) | tocar; o fantasma segue o dedo e a peça entra ao soltar |
| Traçar esteira/cano/trilho/muro/poste | arrastar com o botão esquerdo | arrastar com um dedo |
| Girar | R (Shift+R ao contrário) | botão Girar |
| Remover (peça ou árvore/rocha) | X, depois clicar ou arrastar um retângulo | botão Remover |
| Desfazer / cancelar | Ctrl+Z / Esc ou clique direito | botões |
| Câmera | arrastar sem peça, botão do meio ou direito; roda ou +/−; Q/E; WASD | 1 dedo sem peça; 2 dedos = mover + pinça |

Fantasma verde = pode, vermelho = não pode (a dica em cima diz o motivo: ocupado, água, obstáculo, jazida que falta),
cinza = já está igual. Setas mostram as portas: branca entra, amarela sai.
Esteira traçada faz a curva em L sozinha e escolhe as pontas: **início** quando nada a alimenta, **fim** (para-choque)
quando nada recebe na frente, **reta** quando está ligada — e refaz isso nos vizinhos quando se põe ou remove algo.
Traçar por cima de uma esteira existente troca as peças (continuar a partir de um fim o transforma em reta).

## Pastas
| Pasta | O quê |
|---|---|
| `nucleo/` | `Grade` (tiles, chunks, cantos, rotação, portas no mundo), `Registro` (autoload, carrega os JSON), `RelogioSim` (passo fixo) |
| `mundo/` | `GeradorMundo` (terreno, clima, bioma, água), `Distribuicao` (jazidas, obstáculos, enfeites por hash do tile), `ChunkDados` |
| `construcao/` | `MapaOcupacao` (regras de colocar: área, água, obstáculo, jazida, cantos), `EsteiraElevada` (planeja pilares nos cantos), `Construtor` (planos de peça/traço/remoção, pontas automáticas, desfazer) |
| `logistica/` | `EsteiraCaminho` (linha inteira = 1 objeto, itens por espaços), `Braco` (pega atrás, solta na frente) |
| `maquinas/` | `Maquina` (receita, estados, dorme quando travada) |
| `simulacao/` | `Fabrica` (simula tudo que está no mapa: esteiras em caminhos com carga lateral, portas, braços, máquinas, baús, energia, combustível, munição da torre, estações; remonta a cada mudança guardando os itens), `DesenhoItens` |
| `energia/` | `RedeEnergia` (postes, cobertura, satisfação por rede, combustível dos geradores) |
| `transporte/` | `GrafoTrilhos` (montado do mapa: reta, curva 3×3 em arco, fim de linha, sinais, estações; A*, blocos, reserva), `Trem` (anda numa trilha planejada, freia em bloco ocupado, para centrado na estação, troca carga, inverte em linha sem saída), `DesenhoTrens` |
| `ambiente/` | `Poluicao` (por chunk: emite, espalha, o bioma absorve), `DesenhoPoluicao` (camada roxa, tecla P) |
| `inimigos/` | `MarchaAranha` (marcha trípode + IK), `Aranha` (nó visual, golpe e morte), `Colonia` (ninhos, poluição → aranhas, ataques, muro no caminho, torres, expansão), `DesenhoColonia` |
| `render/` | `DesenhoLotes` (MultiMesh de esteira/cano/trilho por chunk), `Efeitos` (fumaça, ícones de estado, destroços), `material_pf.gdshader` (material único: vento, esteira rolando, pulso, boiar), `terreno.gdshader`, `Materiais`, `DesenhoChunk`, `animacao/Animador` |
| `interface/` | `ControleConstrucao` (toda a entrada: separa gesto de construir de gesto de câmera), `BarraConstrucao` (UI por código), `Fantasma` (prévia verde/vermelha), `RoteiroTeste` (cliques/toques injetados) |
| `cenas/` | `menu` (menu inicial), `mundo_demo` (o jogo: modos novo/continuar/demonstração), `CameraJogo` |
| `progressao/` | `Pesquisa` (árvore, pacotes, o que libera) |
| `testes/` | `executar.gd` + `test_*.gd` (64.000+ verificações) |
| `dados/` | `itens`, `receitas`, `estruturas` (regras), `biomas`, `inimigos` (poluição, ninhos, aranhas, expansão, torre), `menu_construcao` (abas, nomes, textos de bloqueio), `modelos` (gerado) |

## Decisões de arquitetura
- **Lógica separada do desenho.** Tudo em `nucleo/ mundo/ construcao/ logistica/ maquinas/ energia/ transporte/` e
  `MarchaAranha` é RefCounted puro, testável sem janela. Os nós só desenham e animam.
- **Mundo sem estado.** Cada tile é função da semente; chunk nenhum depende de outro (testado: sem costura).
- **Escala.** Esteira = 1 objeto por linha (custo não cresce com o comprimento); máquinas dormem quando travadas;
  desenho por MultiMesh (1 chamada por tipo de modelo por chunk); 1 material compartilhado por cor.
- **Próximo passo de desempenho:** mover `EsteiraCaminho`, `Maquina` e `RedeEnergia` para C++ (GDExtension)
  mantendo a mesma interface — os testes atuais viram a especificação.

## Referências estudadas (só ideias, código próprio)
`Apps/ColecaoFactory/codigos` (Mindustry, shapez.io, OpenTTD — GPL): esteira por espaços entre itens (shapez),
blocos de sinal e reserva (OpenTTD), máquina que dorme (Mindustry). Nada foi copiado.
