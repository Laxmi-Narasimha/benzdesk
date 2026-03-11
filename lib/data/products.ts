export interface Product {
    id: string;
    name: string;
    features: string[];
    subProducts?: Product[]; // For nested lists like in "Handling Solutions"
}

export interface Category {
    id: string;
    name: string;
    products: Product[];
}

export const productsData: Category[] = [
    {
        id: 'desiccants-packaging',
        name: '1. Desiccants for Packaging',
        products: [
            {
                id: 'c-dry',
                name: 'C DRY Desiccants',
                features: [
                    'Company-level certifications: Benz Packaging operates under ISO 9001:2015 (quality), ISO 14001:2015 (environment) and OHSAS 18001:2007 (health & safety).',
                    'Eco-friendly & inert: made from natural clay and sealed in Tyvek pouches to avoid chemical interaction with packaged goods.',
                    'High adsorption: can absorb 50–100 % of their own weight.'
                ]
            },
            {
                id: 'propasec',
                name: 'Propasec Desiccants',
                features: [
                    'Standards compliant: produced according to DIN 55473:2001-02 and certified to DIN, NFH 00320/00321 and U.S. MIL specifications.',
                    'FDA-approved: safe for contact with food and medical products.',
                    'Defined absorption capacity: each unit absorbs ≥ 6 g of water vapour at 23 ± 2 °C and 40 % RH.',
                    'Recyclable materials and available in multiple sizes.'
                ]
            }
        ]
    },
    {
        id: 'desiccants-containers',
        name: '2. Desiccants for Containers',
        products: [
            {
                id: 'be-dry',
                name: 'BE Dry Desiccants',
                features: [
                    'High absorption: calcium-chloride formulation absorbs over 250 % of its weight, keeping humidity below the dew point.',
                    'Safe composition: non-toxic and designed for automotive & engineering products.'
                ]
            },
            {
                id: 'propadry',
                name: 'Propadry Desiccants',
                features: [
                    'DMF-free composition: free from dimethyl fumarate (DMF), ensuring safety during transport and storage.',
                    'Condensation control: hygroscopic salt in a breathable membrane captures moisture to prevent "container sweat".',
                    'Available in chains & trays for container rain protection.'
                ]
            },
            {
                id: 'sanidry',
                name: 'Sanidry Desiccant',
                features: [
                    'ISO-certified manufacture: produced under ISO 9001:2015 and ISO 14001:2015; uses environmentally safe materials.',
                    'DMF-free: composition is free from dimethyl fumarate.',
                    'High absorption capacity: rated at 500 % moisture absorption.',
                    'Coverage & duration: protects spaces up to 30 m³ for up to 3 months.',
                    'Tray design: breathable membrane turns absorbed moisture into liquid that remains contained even if overturned.'
                ]
            }
        ]
    },
    {
        id: 'heat-sealing',
        name: '3. Heat Sealing Film – Shrink Films',
        products: [
            {
                id: 'shrink-films',
                name: 'Shrink Films',
                features: [
                    'Multi-layer design: exterior coating prevents the core from melting during high-heat shrinkage; inner layer ensures a tight seal.',
                    'Confidentiality option: ultra-intense heat-seal films provide tamper-evident packaging.',
                    'Usage guidelines: store below 29 °C (85 °F) with relative humidity 55–70 %, avoid direct sunlight, and use within six months.',
                    'Formats available: rolls, sheets, 2-D and 3-D bags.'
                ]
            }
        ]
    },
    {
        id: 'temp-humidity',
        name: '4. Temperature & Humidity Indicators',
        products: [
            {
                id: 'descending-temp',
                name: 'Descending Temperature Indicators',
                features: [
                    'Irreversible colour change: permanently indicates a drop below 2 °C or 0 °C.',
                    'Reaction time: activates after 30–90 minutes of exposure with ± 1 °C accuracy.',
                    'Shelf life: approximately 2 years from production.',
                    'Ideal for: cold-chain applications such as vaccines and biologics.'
                ]
            },
            {
                id: 'ascending-temp',
                name: 'Ascending Temperature Indicators',
                features: [
                    'Colour shift on heat: shows when temperatures exceed preset limits (–18 °C to +37 °C).',
                    'High-temperature series: windows available up to 290 °C for industrial use.'
                ]
            }
        ]
    },
    {
        id: 'clear-coat',
        name: '5. Clear Coat Spray',
        products: [
            {
                id: 'clear-coat-spray',
                name: 'Clear Coat Spray',
                features: [
                    'VCI technology: transparent coating releases vapour-phase corrosion inhibitors to stop rust.',
                    'Heat-resistant & weatherproof: suitable for outdoor items like balcony railings and garden furniture.',
                    'Packaging & storage: supplied in 429 ml (300 g) cans; store between 4 °C and 40 °C.',
                    'Application tip: spray evenly; don’t wipe if rust prevention is desired.'
                ]
            }
        ]
    },
    {
        id: 'alum-vacuum-barrier',
        name: '6. Aluminium Vacuum Barrier Film',
        products: [
            {
                id: '3-layer',
                name: '3-Layer Film',
                features: [
                    'Aluminium barrier: three layers provide strong protection against oxygen, moisture and contaminants.',
                    'Formats: 130 GSM sheets, 2-D and 3-D bags; suitable for foods and electronics.'
                ]
            },
            {
                id: '4-layer',
                name: '4-Layer Film',
                features: [
                    'Enhanced barrier: four layers including robust aluminium ensure an impenetrable shield.',
                    'High opacity & stiffness: bright white backing; excellent machinability and printability.',
                    'Recyclable with good moisture/gas barrier properties.'
                ]
            }
        ]
    },
    {
        id: 'map-bags',
        name: '7. MAP Bags & Moisture Pads',
        products: [
            {
                id: 'farmfresh-bags',
                name: 'FarmFresh+ Bags',
                features: [
                    'Antimicrobial & anti-fog films: inhibit microbial growth and prevent condensation.',
                    'Biodegradable & food-grade: odourless biodegradable polyethylene; safe for food contact.'
                ]
            },
            {
                id: 'farmfresh-pads',
                name: 'FarmFresh+ Moisture Pads',
                features: [
                    'FDA-approved: safe for direct contact with food.',
                    'Shelf-life extension: absorb excess moisture to delay spoilage and maintain appearance.',
                    'Enhanced safety: dryer environment reduces bacterial growth, lowering food-borne illness risk.',
                    'Improved customer experience: fresher, firmer produce increases customer satisfaction.'
                ]
            }
        ]
    },
    {
        id: 'temp-humidity-add',
        name: '8. Temperature & Humidity Indicators (Additional)',
        products: [
            {
                id: 'humidity-cards-add',
                name: 'Humidity Indicator Cards',
                features: [
                    'Real-time moisture check: cards display a visible colour change from blue to pink as humidity levels rise, giving an immediate indication of moisture exposure.',
                    'Reversible colour change: when humidity drops below the indicated level, the spot returns to blue; cards can therefore be reused if kept dry.',
                    'Storage guidelines: to maintain accuracy, store cards in an airtight container with a desiccant; replace the desiccant if the container is opened more than three times.',
                    'Safety note: avoid direct sunlight, rain and snow; if the indicator’s chemicals contact eyes, flush with water for at least 15 minutes and seek medical attention.'
                ]
            },
            {
                id: 'ascending-temp-add',
                name: 'Ascending Temperature Indicators',
                features: [
                    'Monitoring range: tracks temperatures from –18 °C to +37 °C with ± 1 °C sensitivity and has a 3-year shelf life.',
                    'Exposure duration insight: indicates not only when a threshold temperature is exceeded but also the duration of exposure to elevated temperatures.',
                    'High-temperature series: available windows respond at temperatures between 29 °C and 290 °C; colour changes are irreversible and clearly show the maximum temperature reached.',
                    'Durable labels: oil-, water- and steam-resistant; labels do not delaminate when removed and can be affixed to inspection reports for permanent records.'
                ]
            }
        ]
    },
    {
        id: 'alum-vacuum-barrier-detailed',
        name: '9. Aluminium Vacuum Barrier Film – 3-Layer (Detailed)',
        products: [
            {
                id: '3-layer-detailed',
                name: '3-Layer Film',
                features: [
                    'Triple-layer structure: includes an aluminium barrier that creates an impermeable shield against oxygen, moisture and contaminants.',
                    'Compliance: Meets U.S. military standard MIL-B-131 for fabric- and fibre-free barrier materials.',
                    'Heat-sealable composite: consists of a tough biaxially oriented polymer film adhered to a metallic foil and a third layer of polyethylene for strong seals.',
                    'Formats & customisation: available as 130 GSM sheet rolls, 2-D bags, 3-D bags (with or without flap) and custom sheets.',
                    'Applications: suitable for food products and sensitive electronic components requiring long-term barrier protection.'
                ]
            }
        ]
    },
    {
        id: 'vci-film',
        name: '10. VCI Film',
        products: [
            {
                id: 'general-certs-vci',
                name: 'General Certifications (all BENZ VCI Films)',
                features: [
                    'Comprehensive compliance: BENZ VCI films are certified to numerous international standards, including TRGS 615, ASTM D1748-02, DIN ISO EN 60068-2-30, DIN 50017, DIN ISO 9227:2012-9, TL 8135-0002, RoHS & REACH, NACE TM0208-2008, MIL-PRF-22019E, JIS Z 1535:2014 & JIS Z 0208, and are approved by the FDA for equipment packaging.'
                ]
            },
            {
                id: 'vci-stretch',
                name: 'VCI Stretch Film',
                features: [
                    'Coextruded strength & stretch: Designed to provide exceptional puncture resistance and load retention; allows gauge reduction and secure wrapping of heavy or irregular loads.',
                    'Multi-metal protection: Formulated to protect both ferrous and non-ferrous metals.',
                    'Hand & machine grades: Available in hand-grade and machine-grade variants with thicknesses ranging from 9 µm to 55 µm, enabling customization for various applications.',
                    'Recyclable: Film is recyclable, supporting sustainability initiatives.'
                ]
            },
            {
                id: 'vci-bio',
                name: 'VCI Bio Film',
                features: [
                    'Eco-conscious alternative: A compostable film that offers superior mechanical properties and stability compared to typical biodegradable films.',
                    'Certifications: Holds certifications under DIN, EN 13432, and ASTM D6400 for compostability.',
                    'Heat & water-stable: Remains stable during use, making it suitable for organic waste collection and community composting programs.'
                ]
            },
            {
                id: 'multimetal-vci',
                name: 'Multimetal VCI Film (generic)',
                features: [
                    'Multi-metal compatibility: Designed to protect a variety of metals simultaneously, eliminating the need for different films for different metals.',
                    'ISO/CE/FDA compliance: As with other films, manufactured under ISO 9001:2015 and ISO 14001:2015 and approved by CE and FDA (company-level certifications).'
                ]
            }
        ]
    },
    {
        id: 'vci-diffusers',
        name: '12. VCI Diffusers',
        products: [
            {
                id: 'propatech-vci-noxy',
                name: 'Propatech VCI Noxy',
                features: [
                    'Patented spring dispersal system: Ensures even diffusion of VCI molecules into hard-to-reach cavities.',
                    'Large coverage: Protects up to 10 m³ of volume; 35 g units cover ~3.5 m³.',
                    'Moisture-tolerant: Provides corrosion protection even when moisture is present.'
                ]
            },
            {
                id: 'vci-25-emitters',
                name: 'VCI 25 Emitters',
                features: [
                    'Dual-action pouches/foam: Slow-release pouches absorb moisture and pollutants while emitting VCI vapours.',
                    'Size range: Available in 8 g, 10 g, 20 g and 50 g units; bulk options for large enclosures.',
                    'Residue-free: Leaves no residue on metals and provides long-term protection inside cabinets, toolboxes and voids.'
                ]
            },
            {
                id: 'vci-chips',
                name: 'VCI Chips',
                features: [
                    'Two-sided impregnation: VCI is embedded on both surfaces for easy placement within packages or between layers.',
                    'Versatile format: Small chips can be dropped into boxes, crates or enclosures to protect metal parts without direct contact.',
                    'Recycled content: Manufactured with recycled materials for sustainability.'
                ]
            },
            {
                id: 'vci-emitters',
                name: 'VCI Emitters',
                features: [
                    'High-efficiency dispersal: Engineered to reach concealed areas and deposit an invisible molecular layer on metal surfaces.',
                    'Multi-size availability: Offered in various sizes to match different packaging volumes.',
                    'Recycled content: Utilizes recycled materials where possible.'
                ]
            },
            {
                id: 'vci-foam',
                name: 'VCI Foam',
                features: [
                    'High emanation capacity: Foam matrix holds and slowly releases VCI vapours, making it ideal for electronics and electrical cabinets.',
                    'Multi-metal protection: Suitable for ferrous and non-ferrous metals; powder-free composition prevents contamination.',
                    'Recyclable material: Eco-friendly and reusable.'
                ]
            },
            {
                id: 'vci-strip',
                name: 'VCI Strip',
                features: [
                    'Interior pipe/tube protection: Flexible LDPE strips infused with VCI protect the insides of tubes, pipes and conduits.',
                    'Size range: Available diameters from 6 mm to 12 mm; easy insertion and removal.',
                    'Halogen-free formulation: Contains no halogens, heavy metals or sulphur; vapour does not interfere with subsequent processes like welding.',
                    'Ease of use: Simply insert strip into the tube and cap; VCI vapour saturates the internal air space.'
                ]
            }
        ]
    },
    {
        id: 'handling-solutions',
        name: '15. Handling Solutions',
        products: [
            {
                id: 'on-demand-paper',
                name: 'On-Demand Paper Systems',
                features: [],
                subProducts: [
                    {
                        id: 'paper-cushioning',
                        name: 'Paper Cushioning',
                        features: [
                            'Heavy-weight protection: PaperSY system produces tear-resistant and highly malleable paper pads (80 GSM, 110 GSM & 135 GSM) to block and brace heavy items inside cartons.',
                            'High compressive strength: Outstanding cushioning and compression performance for industrial goods.',
                            'Efficient creasing technology: Maximises material usage; ergonomic machine design with touch panel/foot pedal controls and noise reduction.',
                            'Positive sustainability image: Paper is recyclable and generally well-received by end customers.'
                        ]
                    },
                    {
                        id: 'paper-void-fill',
                        name: 'Paper Void Fill',
                        features: [
                            'Eco-friendly filler: Paper-based void fill material with Forest Stewardship Council (FSC) certification, ensuring responsible sourcing.',
                            'Shock absorption: Large-volume but lightweight paper pads provide excellent cushioning and secure products against breakage.',
                            'Flexible use: Softness and flexibility make the system suitable for void filling and light wrapping; available in various machine models to fit customer requirements.'
                        ]
                    }
                ]
            },
            {
                id: 'on-demand-air',
                name: 'On-Demand Inflatable Air Systems',
                features: [
                    'Customisable air cushions: Offer a range of film thicknesses—25 µm for lightweight items, 50 µm standard and 100 µm for heavy goods/airfreight.',
                    'Specialty films: Options include antistatic ESD films for electronics and bio-based films for environmentally conscious customers.',
                    'Branding: Custom printing available to align cushioning with corporate logos or instructions.'
                ],
                subProducts: [
                    {
                        id: 'air-column-bags',
                        name: 'Air Column Bags',
                        features: [
                            'Pre-formed columns that inflate on demand to create rigid air chambers around fragile goods; provide instant, high-level cushioning.'
                        ]
                    },
                    {
                        id: 'air-cushions',
                        name: 'Air Cushions',
                        features: [
                            'Lightweight pillows for general void fill and surface protection; designed for reliable shock resistance during shipping.'
                        ]
                    }
                ]
            },
            {
                id: 'pkg-foams',
                name: 'Packaging Foams (EPE/EVA)',
                features: [
                    'High impact absorption: Expanded polyethylene (EPE) and ethylene-vinyl acetate (EVA) foams protect against vibration and shock during transport.',
                    'Custom shapes: Foam inserts can be cut or moulded to fit specific product contours, reducing movement inside packaging.',
                    'Reusable & recyclable: Many foam grades are recyclable and can be reused for multiple shipments.'
                ]
            },
            {
                id: 'mailer-bags',
                name: 'Mailer Bags',
                features: [],
                subProducts: [
                    {
                        id: 'paper-mailers',
                        name: 'Paper Mailers',
                        features: ['Made from recyclable kraft paper; often FSC-certified; some variants include padded interiors for extra protection.']
                    },
                    {
                        id: 'poly-mailers',
                        name: 'Poly Mailers',
                        features: ['Durable multi-layer plastic envelopes that are tear- and moisture-resistant; available in tamper-evident or biodegradable formats.']
                    },
                    {
                        id: 'bubble-mailers',
                        name: 'Bubble Mailers',
                        features: ['Poly or paper mailers lined with bubble cushioning for fragile items.']
                    }
                ]
            },
            {
                id: 'propaflex',
                name: 'Propaflex Surface-Protective Sleeves',
                features: [
                    'Co-extruded PE film: Flexible honeycomb-like structure used to wrap metal shafts, tubes and other finished products; prevents scratching and abrasion.',
                    'Recyclable & re-usable: Designed for multiple cycles; easy to cut and apply.'
                ]
            },
            {
                id: 'handling-aids',
                name: 'Additional Handling Aids',
                features: [
                    'Battery-Powered Plastic Strapping Tool: Portable tool for tensioning and sealing polyester/PP straps; improves bundling efficiency.',
                    'Tip-n-Tell Indicators: Self-adhesive labels with tamper-proof indicators that show if a package has been tilted beyond a certain angle during transport.',
                    'Honeycomb Paper Sleeves: Biodegradable paper sleeves with a honeycomb structure providing cushioning and surface protection for bottles and jars.'
                ]
            }
        ]
    },
    {
        id: 'rust-removers',
        name: '13. Rust Removers',
        products: [
            {
                id: 'neutral-rr',
                name: 'Neutral Rust Remover (Neutral RR)',
                features: [
                    'pH-neutral & biodegradable: dissolves rust without damaging base metal; safe for use on various metals and non-metals.',
                    'Non-toxic & odourless: eliminates the need for abrasive cleaning; safe on skin.',
                    'Heavy-rust capability: breaks the iron-oxide bond and removes even heavy rust.',
                    'Short-term protection: leaves a thin film for temporary corrosion protection after cleaning.',
                    'Easy application: soak parts at ~50 °C (ultrasonic recommended); no scrubbing or brushing; safe disposal.'
                ]
            },
            {
                id: 'acidic-rr',
                name: 'Acidic Rust Remover (RR 125 A)',
                features: [
                    'Phosphoric-acid formulation: quickly dissolves iron oxide and removes heat scale, flux and other oxides from steel, stainless steel, brass, copper and aluminium.',
                    'Controlled etching: gently etches iron allowing longer soak times; forms a thin iron-phosphate coating for added rust prevention.',
                    'Use sequence: dip component, rinse with deionised water, neutralise (e.g., Loc Rust 152 K), dry, then apply Rust Preventive Oil and BENZ VCI packaging for long-term protection.',
                    'Suitable for ferrous metals and engineered for compatibility with the Loc Rust RP Oils system.'
                ]
            }
        ]
    },
    {
        id: 'rust-prev-oils',
        name: '14. Rust Preventive Oils',
        products: [
            {
                id: 'short-term-oils',
                name: 'Short-Term Rust Preventive Oils',
                features: [],
                subProducts: [
                    {
                        id: 'loc-rust-dw-791',
                        name: 'Loc Rust DW 791',
                        features: [
                            'Dry-to-touch, ultra-low viscosity: produces a clean, non-sticky film with excellent coverage and minimal consumption.',
                            'Fast drying: dries within 2–3 minutes.',
                            'Excellent dewatering & degreasing; ideal as a cleaning medium and for in-process rust prevention.'
                        ]
                    },
                    {
                        id: 'loc-rust-rp-100',
                        name: 'Loc Rust RP 100',
                        features: [
                            'Light, soft oily film; safe for sheet-metal and precision parts during transit and storage.',
                            'Good coverage & low viscosity: thin film means lower consumption.',
                            'Quick drying: typically dries within 8–10 minutes.',
                            'Easy removal: cleans off with alkaline cleaners; recommended for sheet-metal components, engine parts, shafts and wires.'
                        ]
                    }
                ]
            },
            {
                id: 'medium-term-oils',
                name: 'Medium-Term Rust Preventive Oils',
                features: [],
                subProducts: [
                    {
                        id: 'loc-rust-793-sh',
                        name: 'Loc Rust 793 SH',
                        features: [
                            'Thin, very soft waxy film with excellent water displacement; suited for forging and casting applications.'
                        ]
                    },
                    {
                        id: 'loc-rust-795-hf',
                        name: 'Loc Rust 795 HF',
                        features: [
                            'High flash-point oil with light film; strong resistance to humidity and salt spray; low evaporation, making it ideal for multi-metal protection.'
                        ]
                    },
                    {
                        id: 'loc-rust-sp',
                        name: 'Loc Rust SP (Spray)',
                        features: [
                            '6-in-1 multifunction: prevents corrosion, lubricates, penetrates rusted/sticky parts, displaces moisture, cleans surfaces and reduces noise/chatter.'
                        ]
                    },
                    {
                        id: 'loc-rust-793-pd',
                        name: 'Loc Rust 793 PD',
                        features: [
                            'Smooth, oily film with excellent water displacement; intended for sheet-metal and precision parts during shipment and storage.'
                        ]
                    }
                ]
            },
            {
                id: 'long-term-oils',
                name: 'Long-Term Rust Preventive Oils',
                features: [],
                subProducts: [
                    {
                        id: 'loc-rust-793-s',
                        name: 'Loc Rust 793 S',
                        features: [
                            'Soft waxy protective film that neutralises fingerprints and provides indoor/outdoor protection for multi-metals.'
                        ]
                    },
                    {
                        id: 'loc-rust-793-pu',
                        name: 'Loc Rust 793 PU',
                        features: [
                            'Dry-type oil forming a slightly thick oily film; designed for mechanical parts of mild steel requiring storage for more than two years.'
                        ]
                    },
                    {
                        id: 'loc-rust-793-p',
                        name: 'Loc Rust 793 P',
                        features: [
                            'Soft, sticky/oily film with excellent water displacement; forms a strong protective layer over highly finished components (tools, fasteners, strips).',
                            'Exceptional salt- and seawater resistance, making it ideal for export applications.'
                        ]
                    }
                ]
            }
        ]
    }
];
