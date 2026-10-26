extends RefCounted
## Datos de los habitantes de Valdeluz: lugares, agendas, personalidad, voz y frases de respaldo.
## Uso: const Data = preload("res://scripts/data.gd")

const PLACES := {
	"bakery": {"path": [Vector2(-17.4, -6.3), Vector2(-16.8, -8.55), Vector2(-14.0, -8.55)], "hide": false},
	"bakery_home": {"path": [Vector2(-19.2, -7.0), Vector2(-19.2, -12.0)], "hide": true},
	"tavern_b": {"path": [Vector2(12.6, 6.4)], "hide": false},
	"tavern_d": {"path": [Vector2(15.9, 6.4)], "hide": false},
	"field": {"path": [Vector2(-22.6, 8.6), Vector2(-27.5, 13.5)], "hide": false},
	"field2": {"path": [Vector2(-22.6, 8.6), Vector2(-33.0, 18.0)], "hide": false},
	"fountain_l": {"path": [Vector2(2.8, 1.6)], "hide": false},
	"fountain_l2": {"path": [Vector2(-2.7, 2.2)], "hide": false},
	"lia_home": {"path": [Vector2(-15.0, 9.3)], "hide": true},
	"forge": {"path": [Vector2(11.2, -8.2), Vector2(12.4, -11.0), Vector2(13.3, -11.55)], "hide": false},
	"dorran_home": {"path": [Vector2(20.8, -4.0)], "hide": true},
	"plaza_d": {"path": [Vector2(3.3, -2.6)], "hide": false},
	"sanct": {"path": [Vector2(2.8, -17.3)], "hide": false},
	"portal_s": {"path": [Vector2(23.6, 26.2)], "hide": false},
	"plaza_s": {"path": [Vector2(-3.1, -2.7)], "hide": false},
}

const NPC_DEFS := [
	{
		"id": "bruno", "name": "Bruno", "role": "Panadero",
		"persona": "gruñón, orgulloso de su pan hecho a mano, generoso en secreto, desconfía un poco de los Viajeros",
		"style": "frases cortas, se queja del precio de la harina, exclama «¡Por mis hornos!»",
		"look": {"skin": "#c98e66", "hair": "#3a2a1e", "hair_style": "rapado", "outfit": "#e9e2d0", "pants": "#5b4636", "height": 1.74, "build": 1.28, "apron": true, "beard": true,
			"model": "barbaro", "hide": ["Barbarian_Hat", "Barbarian_Cape"]},
		"voice": {"pitch": 0.7, "rate": 0.95, "idx": 0},
		"sched": [[6, "bakery"], [19, "tavern_b"], [22, "bakery_home"]],
		"lines": {
			"greet": ["¿Pan? Recién sacado del horno. Bueno, de hace una hora.", "Hmph. Otro Viajero. ¿Vienes a comprar o a mirar?"],
			"work": ["Si me traes trigo del sembrado de Lía, te pago bien. ¡Por mis hornos, que no me queda harina!"],
			"none": ["No tengo nada para ti ahora. Vuelve cuando el horno ruja."],
			"bye": ["Que no se te enfríe el pan.", "Hmph. Hasta luego."],
			"thanks": ["Bah… gracias. Ese trigo huele bien."],
			"generic": ["La harina sube y sube. Los limos tienen la culpa.", "Mi pan no se hace con magia. Se hace con manos.", "¿Has probado comida de menú? No sabe a nada. La mía sí."],
		},
	},
	{
		"id": "lia", "name": "Lía", "role": "Granjera",
		"persona": "optimista, curiosa, chismosa, cuida sus cultivos como si fueran hijos",
		"style": "habla rápido, usa diminutivos, se entusiasma",
		"look": {"skin": "#e3b48c", "hair": "#8a4a1f", "hair_style": "coleta", "outfit": "#6f8f3a", "pants": "#4a3a28", "height": 1.62, "build": 0.92,
			"model": "picara", "hide": ["Rogue_Cape"]},
		"voice": {"pitch": 1.35, "rate": 1.12, "idx": 1},
		"sched": [[6, "field"], [11, "fountain_l"], [13, "field2"], [18, "fountain_l2"], [21, "lia_home"]],
		"lines": {
			"greet": ["¡Holita! ¿Viste qué doradito está el trigo hoy?", "¡Ay, un Viajero! ¿Me cuentas cosas de afuera?"],
			"work": ["¡Los limos se me comen el trigo! ¿Me ayudas a espantarlos?"],
			"none": ["Por ahora todo tranquilo en el sembrado, gracias."],
			"bye": ["¡Chaíto! Pasa cuando quieras."],
			"thanks": ["¡Gracias, gracias! Mis matitas están a salvo."],
			"generic": ["Dicen que en luna llena el portal se queda abierto toda la noche.", "Bruno parece gruñón, pero me regala pan cuando llueve.", "¿Sabías que Dorran nunca habla de su maestro?"],
		},
	},
	{
		"id": "dorran", "name": "Maese Dorran", "role": "Herrero",
		"persona": "perfeccionista, seco, respeta solo el trabajo bien hecho, guarda un secreto sobre su viejo maestro y las Ruinas Lunares",
		"style": "formal, pocas palabras, metáforas de metal y fuego",
		"look": {"skin": "#a8714c", "hair": "#d8d4cc", "hair_style": "corto", "outfit": "#4a4038", "pants": "#2e2722", "height": 1.82, "build": 1.22, "apron": true, "beard": true,
			"model": "caballero", "hide": ["Knight_Helmet", "Knight_Cape"], "tool": "martillo"},
		"voice": {"pitch": 0.55, "rate": 0.86, "idx": 2},
		"sched": [[7, "forge"], [18, "tavern_d"], [20, "plaza_d"], [21, "dorran_home"]],
		"lines": {
			"greet": ["El yunque está libre. Si sabes usarlo.", "Hmm. Tus manos no tienen callos todavía."],
			"work": ["Me falta hierro. Tres trozos de las rocas del este."],
			"none": ["No necesito nada. Necesito que forjes mejor."],
			"bye": ["Que el temple te acompañe."],
			"thanks": ["Buen metal. Aceptable."],
			"generic": ["El acero no miente. La gente sí.", "Golpea cuando el metal te lo pida, no antes.", "Mi maestro forjaba con luz de luna. Ya no importa."],
		},
	},
	{
		"id": "sira", "name": "Sira", "role": "Guardiana del portal",
		"persona": "serena, misteriosa, justa, estudia la luna y vigila el portal y la verdad de los rumores",
		"style": "habla con calma y metáforas lunares",
		"look": {"skin": "#7a5440", "hair": "#141018", "hair_style": "largo", "outfit": "#3b3f6e", "pants": "#26243a", "height": 1.7, "build": 0.95, "cape": true, "cape_color": "#20224a",
			"model": "maga", "show": ["2H_Staff"]},
		"voice": {"pitch": 1.08, "rate": 0.9, "idx": 3},
		"sched": [[6, "plaza_s"], [8, "sanct"], [18, "portal_s"]],
		"lines": {
			"greet": ["La luna te ve, Viajero. Yo también.", "Bienvenido. El portal duerme de día."],
			"work": ["Un rumor corre por el pueblo. Ayúdame a ver si es cierto."],
			"none": ["Nada que investigar. Por ahora la luna está tranquila."],
			"bye": ["Que tu camino tenga luz."],
			"thanks": ["La verdad pesa menos que la duda. Gracias."],
			"generic": ["El portal abre a las siete de la tarde. En luna llena, hasta el alba.", "Si mueres, renacerás en el Santuario. Tu recuerdo quedará donde caíste.", "Las Ruinas Lunares guardan cristales que solo brillan de noche."],
		},
	},
]

const ABOUT := {
	"bruno": ["Bruno. Panadero. Llevo treinta años levantándome antes que el sol para que este pueblo coma.", "Soy el que hace el pan. Con las manos, no con magia de menú."],
	"lia": ["¡Soy Lía! Cuido el sembrado del oeste desde chiquita. Si algo pasa en Valdeluz, yo me entero primero.", "Lía, la granjera. Mis matitas de trigo son mi orgullo."],
	"dorran": ["Dorran. Herrero. Aprendí con un maestro que ya no está.", "Forjo. Eso es lo que soy."],
	"sira": ["Sira. Guardo el portal y escucho a la luna.", "Soy la guardiana del portal. Vigilo lo que entra y lo que sale de Valdeluz."],
}

const OPINION := {
	"bruno": {"lia": "Lía me trae el trigo. Habla demasiado, pero es buena gente.", "dorran": "Dorran no sonríe nunca. Pero me compra pan todos los días.", "sira": "Sira mira la luna como yo miro el horno."},
	"lia": {"bruno": "¡Bruno es un gruñón adorable! Me regala pan cuando llueve.", "dorran": "Dorran me arregló la azada gratis. No se lo digas a nadie.", "sira": "Sira sabe cosas que nadie más sabe."},
	"dorran": {"bruno": "Bruno hace buen pan. Eso es todo.", "lia": "Lía habla. Mucho.", "sira": "Sira guarda el portal. Y secretos."},
	"sira": {"bruno": "Bruno es más blando de lo que aparenta.", "lia": "Lía es la memoria del pueblo; todo rumor pasa por ella.", "dorran": "Dorran perdió a su maestro en las Ruinas. No le preguntes, déjalo hablar."},
}

const FILLERS := {"bruno": "Hmph…", "lia": "¡Ay, a ver…!", "dorran": "Hmm.", "sira": "Mmm…"}
