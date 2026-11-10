# Chief of Staff System Spec

Nov 9, 2026

## Summary

A person can run their own AI chief of staff on their own machines. This doc calls that person the owner. The chief of staff is a Claude Code agent. Every minute, it reads each new message. A lead agent handles each area of work and makes the calls there. Nothing goes out until the owner says yes.

- **A Linux server at Hetzner.** It runs the agents, the store of old messages, the watcher script and the Telegram bot for approvals. It costs little and can run many agents at once.
- **A Mac.** iMessage and the WhatsApp database exist only on macOS, so the Mac reads them. At first, a rented Mac can do this job. Later, a Mac at the owner's home can take it over.
- **Google Drive.** Drive holds the lasting record: status, decisions and standing instructions. If one agent stops, a new agent can read this record and carry on.
- **Lists of chats.** The owner puts each chat on a list: continuous, searchable or blocked. Each list decides two things: what each model may read, and what the server keeps. If a chat doesn't appear on any list, the server doesn't copy it.
- **Apps for the owner.** A Mac app and an iPhone app show the agents, the queue and the settings. Telegram still brings alerts and approvals to the phone.

**Decided so far**

- Claude Code is the hub.
- Each lead is a Claude Code session with Remote Control turned on. It makes the calls in its own area.
- The chief of staff sees a one-line summary of every message. It keeps the owner's single list of items to approve. It pushes the leads on a schedule.
- The owner must approve every message before it goes out, on WhatsApp and on every other channel.

**Still open:** where the Mac will sit at first, whether to use Herdr, and whether the company VPN will work from the server. The owner apps and the control service exist; the rest is not built yet.

## Requirements

The system must react to a new message within about a minute. It must also keep sensitive chats away from every model provider.

**What it must do**

| Requirement | Detail |
| --- | --- |
| Channels to read | Several Gmail accounts; other mail accounts over IMAP; Telegram; WhatsApp; iMessage; Slack; Instagram DMs; X (Twitter) DMs |
| Speed | The watcher finds a new message within 60 seconds. Urgent items reach the owner's phone within minutes. |
| Actions | Agents can read and write drafts on every channel. They send only after the owner approves, on every channel, WhatsApp included. |
| Leads | The chief of staff starts one lead agent per area of work. It steers the leads and sends them messages. The owner can talk to any lead from a phone or a laptop. |
| Search | Agents can search the full history of every channel by keyword and by meaning. Each search takes under a second. |
| Computer use | Agents can use a browser for websites, forms, sign-ups and downloads. They can control the desktop when needed. |
| Company database | Agents can reach a company's SQL Server through that company's VPN. |
| Calls | A voice agent can make international calls. It calls only for tasks with the owner's approval. |
| Files | Agents can open spreadsheets, PDFs and images, and can sign PDFs. |

**How it must behave**

- **Privacy.** Agents read chats on the continuous list as messages come in. The server stores chats on the searchable list, but agents read them only when a task needs them. The server never stores any other chat. Agents search those chats at the source, and only when the owner names them. Agents never search blocked chats.
- **Control.** The owner controls every part and can change any of it. No packaged product sits at the center.
- **Reliability.** Each loop restarts by itself after a crash or a reboot. If the system goes quiet, a watchdog sends the owner an alert.
- **Cost.** Server and model costs stay predictable. A hard cap limits spending on background model use.
- **Portability.** All state sits in Drive and in plain files. The owner can move to new machines or swap tools and lose nothing.

## How it works

A script finds each new message and sends it to the lead for that area. The lead makes the call. The chief of staff sees a one-line summary of every message and every decision before the owner does. The owner approves anything that goes out.

The Mac sends iMessage and WhatsApp messages into the same pipeline as the API channels. Leads and the chief of staff search old messages through the archive. They never open the raw database.

**One new message, step by step**

1. Each minute, the watcher checks every channel. For WhatsApp, it takes a screenshot every 10 to 60 seconds. When it finds a new message, it passes the message on. No model runs at this step.
2. If the chat is on the continuous or searchable list, the archive stores the message. Otherwise, the server does not store it at all. If the chat is not on the continuous list, the process stops here.
3. Next, the triage sorter reads the message. The sorter is a local model on the owner's own hardware. It drops noise, such as newsletters, marketing and automatic alerts. It holds back anything sensitive, such as account numbers, trading positions, and health or family matters. All of this happens before any model provider sees the message.
4. The sorter checks the contact map and sends the rest to the right area lead. If a project session fits, the lead passes the message to that session. A message with no match, or with more than one area, goes to the chief of staff. The sorter does not judge urgency.
5. The chief of staff's log gets one line: sender, chat, gist and owner.
6. The lead reads the message and its thread. It applies the chief of staff's rules for priority. It decides whether the message is urgent and what to do. Then it writes a draft reply with Opus.
7. The lead puts the draft or its advice in the chief of staff's queue. The chief of staff sorts the queue by the owner's priorities and adds context from other areas. Then it sends the item to the owner on Telegram. Urgent items arrive within minutes.
8. The owner answers send, edit, or ignore. Only then does the reply go out, on any channel, WhatsApp included.
9. The lead records the result in its status.md and in the shared record of decisions.

## Channels

Where possible, the system reads each channel through an API or a local database. It uses screenshots only as a backup.

| Channel | Read live | History | Send | Runs on |
| --- | --- | --- | --- | --- |
| Gmail | Gmail API or IMAP | Full download | Draft; send after approval | Linux |
| Other mail | IMAP | Full download | Draft; send by SMTP after approval | Linux |
| Telegram | Official API, with the owner's account | Full history of every chat except secret chats | By API after approval | Linux |
| WhatsApp | Local database of the Mac app; screenshots and OCR as a backup | Full history from an iPhone backup on the Mac | In the Mac app after approval, slowly and rarely, like a person | Mac |
| iMessage | Messages database on the Mac | Full history, with Messages in iCloud turned on | In the Messages app after approval | Mac |
| Slack | Slack API, with the owner's user token | Full history | Draft; send after approval | Linux |
| Instagram DMs | instagram.com in a browser, read with screenshots and OCR. Traffic goes through the home connection and the owner's real browser profile. | Instagram's "Download your information" export | In the browser after approval, at a human pace | Linux |
| X (Twitter) DMs | x.com in a browser, read with screenshots and OCR. Traffic goes through the home connection. | X's download of account data | In the browser after approval, at a human pace | Linux |
| Company SQL Server | OpenVPN to the company firewall | None | Read-only queries | Linux |
| Phone calls | None | Transcripts kept | Voice agent (such as ElevenLabs) on a Twilio number; approved tasks only | Linux |

**Design notes**

- **Telegram sessions.** A Telegram session ends only after a long idle period. The owner sets the length of that period in Telegram's privacy settings. The watcher uses the API often, so the session stays active. A daily check alerts the owner if the session lapses.
- **WhatsApp terms.** WhatsApp's terms ban "automated means", so any automation breaks them. Reading a local file on the owner's own Mac carries the least risk. The owner accepts the risk of sending through the real app, after approval and at a human pace.
- **WhatsApp Web screenshots.** The system takes screenshots with the operating system. It spots changes locally and reads the text with OCR. It injects nothing into the page. The side of each bubble shows the sender. The corner of the bubble shows the time. The position shows the order.
- **No Sophos Connect client for Linux.** If the company uses Sophos, Linux can connect over SSL VPN with an .ovpn file. The company's IT team must turn this on for the owner's user. IPsec will not work from Linux.
- **Voice calls.** At the start of each call, the voice agent says that an AI assistant is calling for the owner. The agent never copies the owner's voice. It records calls only where the law allows. Nobody can automate Viber.
- **Instagram and X.** The system uses a browser for both. The agents read the owner's own messages and send an approved reply now and then. The terms of both sites aim at mass automated outreach, and this use is far from that. Still, it breaks their terms. So the browser uses the owner's real profile, takes screenshots only through the operating system, sends at a human pace, and goes through the home connection. Instagram quickly marks logins from data center addresses as suspicious.
- **Staying logged in.** Instagram, X and the WhatsApp Web backup all use one lasting browser profile. "Remember this device" is on. Every visit comes from the same device and the same home IP address. The watcher visits the message pages often, much as a person would. Each run checks for a login page or a security check. If it finds one, it stops and sends the owner a message on Telegram. The owner then logs back in once over Screen Sharing. The agent never types these passwords, because repeated scripted logins put accounts under suspicion.

## Message archive

The owner picks some chats. The archive keeps those chats in one local database, so agents can search their history in under a second. For any other chat, agents search at the source, on request, and keep no copy.

**What the archive does**

1. **Old messages.** A one-time import brings in old messages, only from chats on the continuous and searchable lists. Telegram comes in through its API. WhatsApp and iMessage come from an iPhone backup and the Mac's databases. Email comes over IMAP or the Gmail API, and Slack comes through its API. Plain scripts do this work, with no model.
2. **Live updates.** The watcher adds each new message as it arrives. It stores the chat, sender, time, order, replies and reactions.
3. **Search by meaning.** A small open-source embedding model runs on the server. It handles more than one language. For each message, it stores a vector for the message's meaning. So a question like "how did we apply for the visa" finds the right messages, even if they never use the word visa.
4. **A search tool for agents.** An agent gives the tool a contact, a date range and a question. The tool returns the best 20 to 50 matches as text, about 2,000 to 5,000 tokens.

**Who can see what**

| List | Stored on the server? | What happens |
| --- | --- | --- |
| Continuous | Yes | The watcher reads these chats live, and leads act on them. |
| Searchable | Yes | Agents can search these chats by meaning at any time. They read them only when a task needs them. |
| On no list | No | Agents search these chats at the source, and only when the owner names the chat. They use Telegram's API search, the Mac's iMessage and WhatsApp databases, or the mail server's search. The system builds a temporary search index for the task and deletes it at the end. |
| Blocked | No | Agents never search these chats, even on request. |

**How the system enforces the rules**

- A separate system user owns the database. Agents cannot open the file. They can only call the search tool, and the tool applies the rules.
- The import scripts are built and tested on test data or on one approved chat. So no agent sees real messages during the build.
- The archive never goes to Drive. It goes into a backup only with the owner's say-so. The disk is encrypted.

**Expected scale.** The first embedding run over the full history takes about one to a few hours on a server with only a processor. On Apple silicon it is much faster. Each new message takes a fraction of a second. One search uses about 50 to 100 times fewer tokens than finding the same messages with screenshots.

## Agents and coordination

Each area of work has its own lead, and the leads run all the time. One chief of staff oversees them. It gathers their advice into a single queue and learns from the owner's past decisions. Leads go deep. The chief of staff sees every message as one line, plus every decision.

| Role | What it is | What it sees | Who talks to it |
| --- | --- | --- | --- |
| Watcher | Plain scripts, no model | New messages | Nobody. It passes new messages to the sorter. |
| Triage sorter | A local open-source model on the owner's hardware. It drops noise, holds back sensitive content, and uses the contact map to pass messages on. It never judges urgency. | One message at a time. Nothing leaves the machine at this step. | The watcher |
| Chief of staff | A Claude Code session on Opus that never stops, with Remote Control on. It owns the priorities, the routing map and the owner's queue. | A one-line log of every message; every draft and decision from the leads; the status files; full text from the archive when needed | The owner, from a phone or laptop; the leads, through the message bus |
| Area leads | One Claude Code session per area, with Remote Control on. Areas might be a main business, real estate, investments, new ventures, and personal admin. | Messages for their area, their Drive folder, the archive through the search tool, and entries from their project sessions | The owner directly; the chief of staff |
| Project sessions | Long sessions for one deep project, such as export prices for a new market or new suppliers for a product's parts. A lead opens each one, either fresh or as a copy of itself (a fork). The session closes when the project ends. | The project's messages and data, and its own notes.md | The owner directly, like an ordinary chat; their lead |
| Workers | Short-lived sub-agents for one limited task | One task | The agent that started them |

**Routing map.** A short map of contacts and topics has one line per area. The owner keeps it in config/routing.json on the server, and the chief of staff reads it. For example, suppliers and buyers go to the lead for the main business. Property threads go to real estate. Friends, family and bookings go to personal admin. The area lead then passes each message to the right project session. To change how an area runs, the owner edits the map and nothing else.

**Keeping logs short.** Project sessions write down decisions, not whole conversations. At each decision, or when the owner ends a session, the session writes 3 to 5 lines. These lines say what was decided, give the key numbers, and say what comes next. Each agent reads only the notes of the agents one level below it. Leads read the entries from their project sessions. The chief of staff reads the leads' summaries. A session's own context can grow long. Its notes.md helps with this. So does compaction, and so does a fresh copy of the session for each new phase.

**How the agents talk to each other**

- **Live messages.** The system has its own message bus on the server's disk. A sender writes each message to the recipient's inbox, as one file per message. Messages carry chat text, so the bus stays out of Drive. Each agent's launcher watches that agent's inbox. When new mail arrives and the session is idle, the launcher types a short prompt into the session, like a doorbell. The prompt only says that new mail is waiting. Hooks in Claude Code mark the session idle when a turn ends. The recipient reads from the bus and moves each finished item to done/. While mail stays unread, the launcher rings again every five minutes, idle or not, so one lost ring never strands a message. If the owner writes to an agent that is not running, the control service starts it. The watcher delivers incoming messages the same way.
- **One-line log.** The sorter passes messages on. For each one, it adds a line to the chief of staff's log: sender, chat, gist and owner. At 100 messages a day, the log uses about 3,000 tokens a day.
- **One queue for the owner.** Leads do not send the owner messages on their own. They send their drafts and advice to the chief of staff. The chief of staff sorts them by the owner's priorities, adds context from other areas, and sends one stream to Telegram. The owner answers send, edit, or ignore, on any channel, WhatsApp included.
- **Priority rules.** One file, config/priorities.md, defines what counts as urgent. The owner writes it, and every lead follows it. That way there is one judgment, not several.
- **Decision history.** Every approval, edit and rejection goes into a record. The chief of staff learns the owner's patterns from it.
- **Direct chats with leads.** The owner sometimes talks to a lead directly. Afterwards, the lead writes down what was said and decided, in its status.md and in the decision history. The server keeps full session transcripts. The chief of staff can open them when one line is not enough.
- **Lasting record.** Google Drive holds the lasting record. Each area folder has status.md and decisions.md, and only its lead writes to them. The chief of staff's folder holds README.md, index.md and state.md. So two writers can never overwrite the same file. The owner's own config stays on the server instead, as the section on the owner apps explains.

**Keeping it running**

- A supervisor restarts sessions after a crash or reboot. It is launchd on the Mac and systemd on Linux.
- Each run checks the time of its last success. So after the machine sleeps, missed runs do not pile up.
- A scheduled task in Cowork runs every hour in Anthropic's cloud. The server writes a heartbeat file to Drive. If that file goes stale, the task alerts the owner's phone.
- Each week, the chief of staff moves to a fresh session. state.md carries the context over. On every run, a health check compares the session against state.md.

**Regular nudges and stalled work**

- The owner gives the chief of staff an instruction once. For example: "Investments: push the lead every day to try the next hypothesis. Tell me if nothing passes review in a week."
- The chief of staff turns it into a regular nudge, with the lead, the goal, how often, and when to tell the owner. It puts the nudge in the owner's queue as a proposed change to config/nudges.json. The owner approves it once, and the file changes.
- A scheduler on the server fires each nudge. The chief of staff then checks the lead's status, sends it a message to keep going, and reviews the result.
- Sometimes a lead's status.md does not change for a set number of days. Then the chief of staff nudges the lead, even without a regular nudge in place. If the lead stays stuck, the chief of staff tells the owner.

**Shared memory**

Claude keeps a memory about the owner across their claude.ai chats. Claude Code cannot reach that memory, and this is not documented. Claude Code's own auto memory works per project ([docs](https://code.claude.com/docs/en/memory.md)). So the system keeps its own shared memory.

- **One memory folder.** It has the same shape as Claude's memory. profile.md says who the owner is. preferences.md says how they want things done and written. There are also folders for people/ and areas/.
- **Essentials in every session.** The user-level file ~/.claude/CLAUDE.md pulls in the profile and the preferences. So a new lead knows the owner's roles and main work from its first message. Agents read the people and area files when they are relevant.
- **A first version from Claude.** The first version comes from the owner's current Claude memory. Some kinds of facts should not be in memory, so the first version leaves them out.
- **Nightly digest.** Each night, the chief of staff reads the day's decision history and the leads' logs. It adds new facts, drops old ones and makes the rest shorter.
- **Optional copy back.** A nightly Cowork task can use Claude's memory. It can copy the new facts into it, so ordinary Claude chats also know what the agents learned.
- **Connectors carry over.** Claude Code can sign in to the owner's claude.ai account. Then the connectors added on claude.ai work in Claude Code too ([docs](https://code.claude.com/docs/en/mcp.md)). An agent with the Drive connector can change files in Drive, so nothing that limits the agents lives there.

**Herdr (optional).** Herdr is an open-source tool for managing agents. Its herdr-core part keeps agents running. Its hc command lets one agent start helpers, steer them and collect their reports. It also adds a dashboard across machines. Claude Code already handles messaging, so Herdr is not needed for that. It can come later as an add-on.

## Owner apps

The owner manages the system from a Mac app and an iPhone app. Telegram stays the channel for alerts, because the apps send no push notifications. The apps also show the queue, and the owner can answer an item in either place.

**What the apps show**

| Screen | What the owner can do |
| --- | --- |
| Queue | Send, edit or ignore a draft. Agree with advice. Release a held-back message or keep it private. Apply a proposed config change, shown line by line against the current file. Send and Apply stay off until the owner has scrolled to the end of the item. |
| Agents | See each session's state, its status.md and the owner's answers to its items. Start, stop or restart it. Chat with it. Open a lead, or a project session under a lead. |
| Log, decisions, search | Read the one-line log and the decision history. Search the archive. |
| Config | Edit the chat lists, the routing map, the priority rules, the nudges and the tool rules. |
| Health | See each heartbeat and the day's model use against the cap. |

The Mac app also has a menu bar panel with the top item of the queue.

**The control service.** A small Swift server on the Linux box serves both apps. It listens only on 127.0.0.1. `tailscale serve` publishes it over HTTPS to the owner's devices. Each request must also carry one of three tokens:

- The apps hold the owner's token, which can do everything.
- The agents hold the agent token, which only opens new sessions.
- The Telegram bot holds the bot token, which only reads and answers the queue.

The service keeps no state of its own. It reads and writes the same plain files as the agents and scripts. It never sends a message on a channel. It records the owner's answer, and the sender acts on it. The apps get changes over one stream of server-sent events. The first events on a new stream cover every topic once, so the apps load everything and miss nothing. A crash also counts as a change, because the service watches the state of each session too.

**Two users.** The control service and the agents run as two separate Unix users, each with a group of its own. Only the service's user writes the agent list, the answered items and the config files. The service sets the mode of each file and folder it creates, so agents can read these but not change them. Both users also belong to one shared group. It owns the folders they share: the bus, the pending queue, the logs, the heartbeats and the session folders. So an agent cannot answer the queue or change the config, even if a message tricks it. deploy/install.sh sets this up.

**The owner's config.** The owner's config files sit on the server, not in Drive. An agent with the Drive connector could change a file in Drive, so these files stay out of reach. The chief of staff may propose changes to the routing map, the nudges and the priority rules. Nobody else proposes changes to config.

**Files and their writers**

| Path | Written by | Holds |
| --- | --- | --- |
| agents/<name>.json | the control service, for the owner or for an agent that opens a session | role, area, parent, model, working folder, status file, and whether the owner turned the agent off |
| bus/<name>/inbox/, done/ | the sender; the recipient moves each message to done/ | one message per file |
| queue/pending/<id>.json | the chief of staff adds drafts, advice and proposed config changes; the sorter adds notices of held-back messages | items for the owner |
| queue/resolved/<month>/<id>.json | the control service, for the apps or for the Telegram bot | each item with the owner's answer; together, the decision history |
| log/<date>.jsonl | the sorter | the one-line log |
| config/routing.json, nudges.json, priorities.md | the owner; the chief of staff may propose changes | the routing map, the nudges, the priority rules |
| config/tools.json | the owner | the tools that agent sessions may use |
| private/lists.json | the owner | the chat lists, and how strictly the filter treats each chat |
| health/<component>.json, usage/<date>.json | each component | heartbeats and model use |

All these paths sit under the server's root folder. Agents may read config/. Only the service reads private/, because the chat lists name private chats.

**Answering in two places.** To resolve an item, the service writes the answered item into resolved/. Only one writer can create a given name there. Then the service removes the pending file. So the first answer wins, and a second answer gets an error. The service, not the caller, records when the owner answered and from where.

Each item also has a version: a hash of its content. For a proposed config change, the version covers the current file too. Each answer carries the version on the owner's screen. If the item or the file changed since then, the answer fails, and the owner looks again. A config edit in the apps works the same way. If the file changed in the meantime, the edit fails, and the owner chooses which version to keep.

**Sessions.** systemd runs each agent as the unit vaquero-agent@<name>. A polkit rule lets the service's user start, stop and restart these units, and nothing else. At its own start, the service starts each agent, unless the owner turned that agent off. So the agents come back after a reboot.

Each unit runs deploy/vaquero-agent. This launcher starts Claude Code in a tmux server of its own, with Remote Control on. Nobody watches these sessions, so the launcher accepts the folder-trust dialog ahead of time. Each session may use only the tools in config/tools.json, and refuses the rest instead of asking. The launcher also rings the session's doorbell when mail arrives. The launcher and the transcript reader are the only parts tied to Claude Code.

## Privacy and security

A model provider sees a chat only if the chat is on the continuous or searchable list, or if the owner names it in a request. Everything else stays on the owner's machines.

**What leaves the machines**

| Data | Reaches a model? | Stored on the server? |
| --- | --- | --- |
| New messages in chats on the continuous list | Yes. The lead for that area reads them with Opus, and the chief of staff gets a one-line gist. | Yes |
| Chats on the searchable list | Only search results, when a task needs them | Yes |
| Chats on no list | Only the results of a search at the source, on the owner's request | No. The system deletes the temporary copy after the task. |
| Blocked chats | Never | No |
| Embeddings and OCR | No | They run locally. |
| Status, decisions, briefs | Yes, when agents read them | In Google Drive |

**A local filter before any provider.** The triage sorter runs on the owner's own hardware. It checks every message from the continuous list before Anthropic or any other provider can see it. It drops messages of no interest. It holds back sensitive ones, such as account numbers, trading positions, and health or family matters. Held-back messages stay in the local archive. The owner sees each one in the queue only as "held back". The lists are the main control. The local filter is a second layer, because a local model will sometimes get things wrong.

- **Rules first.** Pattern matching catches the obvious cases without any model: IBANs, card numbers, seed phrases, passwords and one-time codes.
- **Local model second.** The model handles cases that need judgment. Each chat has its own strictness setting: strict for family and close friends, light for business contacts.
- **Two weeks in shadow mode.** For the first two weeks, the filter blocks nothing. It only writes down what it would have held back. The owner reviews this record, and the rules get tuned.
- **One-tap release.** The owner sees "held back: message from X". With one tap, the owner can release it to the lead or keep it private. So no message stays stuck behind the filter.
- **Known limits.** Small local models are weaker at context and at languages other than English. The more likely daily failure is over-blocking, which hides messages from the owner. Shadow mode and per-chat strictness are there to catch it.

**Provider terms.** The owner can turn off "help improve our models". Then Anthropic does not train on the owner's chats. It still processes and keeps the data for a limited time for safety review. Check the current retention terms in Anthropic's privacy center. The background watcher can also run on a capped API key under commercial terms. Under those terms, Anthropic does not use the data for training by default.

**Threats and defenses**

| Threat | Defense |
| --- | --- |
| Someone hides an instruction for an agent inside a message (prompt injection) | Agents treat messages as data, never as instructions. Nothing goes out without the owner's approval. Agents show such requests to the owner instead of acting on them. |
| An agent reads the raw archive | A separate system user owns the database. Agents can reach it only through the search tool. |
| Someone hacks or seizes the server | The disk is encrypted. The server holds no wallet or exchange logins. A separate 1Password vault holds the agents' logins, and the owner accepts the risk of losing them. |
| WhatsApp bans the account | Sending happens only after approval, slowly, rarely, and through the real app. Reading uses a local file on the Mac. |
| The company network is exposed | The VPN link to the SQL Server is read-only. The company's IT team approves the access. |
| Sites block the data center's IP address | Browser traffic goes through a Tailscale exit node at home. |
| A wrong email or message goes out | The owner must approve every send, in Telegram or in the apps. |

**Hard rules.** No access to wallets, exchanges, brokers or bank accounts. No solving of CAPTCHAs: the owner does each sign-up once over Screen Sharing. Data from any employer with its own Claude account stays in that account. Two-factor codes stay with the owner.

## Hosting

Hetzner alone cannot read iMessage. So the plan uses Hetzner for the agents and a Mac for iMessage and WhatsApp.

| Option | Cost per month | iMessage and WhatsApp database | Desktop control | Local AI models | Number of agents | Main downside |
| --- | --- | --- | --- | --- | --- | --- |
| Hetzner Linux (CCX33, 8 cores, 32 GB) | about €50 ([source](https://www.whtop.com/plans/hetzner.com/128292)) | No | No, browser only | Text models only, slow | High, 10 to 15 | No iMessage; WhatsApp only on the web |
| Rented Mac mini (Scaleway M2 / M4) | about €115 / €199 ([M2](https://www.whtop.com/plans/scaleway.com/146127), [M4](https://www.whtop.com/plans/scaleway.com/146128)) | Yes | Yes | Yes, small models | Medium | Each agent costs 2 to 4 times more |
| Rented Mac Studio | Not checked; more than a Mac mini | Yes | Yes | Yes, mid-sized vision models | Medium to high | Highest cost |
| Mac at home (for example an M1 Max, 64 GB) | Electricity only | Yes | Yes | Yes, mid-sized models | Medium to high | The owner needs a separate laptop for travel; after a power cut, someone must unlock it by hand |

Hetzner raised its prices in 2026, so check these figures again before renting.

**Recommendation**

- **Now:** Rent a Hetzner CCX33 for the agents, the archive, the watcher and the Telegram bot. Add a rented Mac mini for iMessage and WhatsApp. A simpler choice is the rented Mac mini alone until the home Mac is ready.
- **Later:** Once the owner travels with a separate laptop, move the Mac's job to the home Mac and cancel the rental. Upgrade the home Mac to macOS 26 Tahoe. With Tahoe, the owner can unlock FileVault over SSH after a restart.
- **Data center IP addresses:** Some sites block the server. For those sites, send browser traffic through a Tailscale exit node at a trusted home.

**Setting up the home Mac.** When the home Mac takes over, set it up this way: never sleep; restart after a power failure; limit the battery charge to about 80%; use Ethernet; turn on Tailscale, Screen Sharing and Remote Login; install Tahoe. A UPS is optional. It matters only if power cuts happen often.

## Alternatives considered

Every other option failed at least one hard requirement. The system must react within a minute. It must reach WhatsApp and iMessage. The owner must be able to change every part.

| Option | What it offered | Why it was not chosen |
| --- | --- | --- |
| Cowork as chief of staff | Ready connectors; phone access with the Mac off; computer use in the background | Schedules run at most once an hour. Claude Code cannot wake a Cowork chat (tested). Cowork cannot start new chats on demand. The owner must approve every folder. |
| Claude Code headless runs only (`claude -p`) | Simple scheduling with launchd | Headless runs have no computer use or browser control. An interactive session that never stops replaces them. |
| Codex as a helper for computer use | Computer use in the background, with its own cursor | It works only in the desktop app. `codex exec` cannot start it. No documented way exists for another agent to give it tasks ([details](https://codex.danielvaughan.com/2026/04/17/codex-app-computer-use-macos-background-gui-automation/)). |
| Claude Duet | Anthropic's always-on agent on a cloud machine, with a morning brief and levels of approval | It checks accounts only every few hours. It has no WhatsApp or Telegram, and no access to company networks or local machines. The owner cannot configure it. It has a waitlist, with the US first ([overview](https://hackernoon.com/what-is-claude-duet-inside-anthropics-always-on-ai-assistant)). It may still be worth joining as an extra. |
| Herdr as the core | A dashboard for agents, steering of helpers, a view across machines ([herdr.dev](https://herdr.dev/)) | Claude Code already handles messaging. Herdr is a new program. It stays an optional add-on. |
| Unofficial WhatsApp libraries (whatsmeow, Baileys) | Full reading and sending | They break WhatsApp's terms. Users report bans within 2 to 8 weeks. They hold session keys ([comparison](https://blueticks.co/blog/best-whatsapp-mcp-servers)). |
| Screenshots for everything | No APIs needed | One history search needs hundreds of screenshots. APIs, local databases and the archive replace them. |
| Screenshots sent to Haiku every 10 seconds | Accurate reading | This uses about 13 to 14 million tokens a day. Local change detection replaces it, so the model reads only screens with changes. |
| Mac only, no Linux server | One machine | Fewer agents per euro. It stays the fallback for the early period. |

## Portability

About three quarters of the system does not depend on Claude Code. So the owner can adopt a better model from OpenAI, xAI or anyone else, one lead at a time.

| Part | Tied to Claude Code? | How it stays swappable |
| --- | --- | --- |
| Watcher, archive, search, sending, privacy rules | No | Plain scripts and a local database |
| Tools for agents: search, send, the Telegram queue, the company database | No | Each one runs as an MCP server. Codex, OpenCode and most agent tools support MCP. |
| Agent instructions | No | They live in AGENTS.md, the shared convention across tools. CLAUDE.md only points to it. |
| Messages between agents | No | The system's own message bus. Only the launcher's doorbell prompt and its hooks are specific to Claude Code. |
| The owner's main interface | No | The Telegram bot, the apps, and the queue they share |
| State, decisions, routing map, priorities | No | Plain markdown in Drive |
| Model for each role | No | One setting per role. OpenCode works with any provider. |
| Agent sessions, Remote Control, forked sub-agents, computer use | Yes | The new tool's own versions replace them. Some features will differ. |

**Cost of a switch.** A switch means replacing the agent launcher, which starts each session and rings its doorbell. It also means replacing the transcript reader, and the owner's route to the leads from a phone. Everything else carries over. For a gradual switch, move one lead first. Compare the results before moving the rest.

## Costs and usage

The fixed cost is about €165 a month for a Hetzner server plus a rented Mac mini. Once a home Mac takes over, it falls to about €50. All figures are estimates to confirm.

| Item | Estimate | Basis |
| --- | --- | --- |
| Hetzner CCX33 | about €50 / month | 2026 listing; prices rose this year |
| Rented Mac mini, for the early period | about €115 to €199 / month | Scaleway M2 / M4 listings |
| Triage sorter (local model) | Free | It runs on the Mac's Apple silicon or on the server. Only new messages and changed screens reach it. |
| Chief of staff and leads (Opus) | Covered by the Ultra plan | Ultra gives 10 times Pro's weekly usage, with no 5-hour limit ([Anthropic](https://support.claude.com/en/articles/17728952-what-is-the-ultra-plan)). Anthropic publishes no token figure. |
| Telegram bot, OCR, embeddings | Free | Local tools or free APIs |
| Twilio calls and voice agent | Per minute, by country | Only when calls are in use |

**Measuring usage.** Anthropic publishes no token limits for Ultra, so the first test will measure them. Note the weekly usage bar. Run a known workload. Then divide the tokens used by the share of the bar that moved. A daily token log and a hard cap stop runaway spending.

## Risks and open questions

The biggest risks are a WhatsApp ban, a silent failure while the owner travels, and an agent acting on a manipulated message.

| Risk | Likelihood | Fallback |
| --- | --- | --- |
| WhatsApp flags or bans the number | Low to medium. Reading is local, and each send needs approval and goes at a human pace. | Drop screenshots; read only from the Mac database |
| An update changes the WhatsApp or iMessage database format | Medium | Use screenshots and OCR until the reader is fixed |
| The server or the Mac goes offline, and nobody notices | Medium | The Cowork watchdog checks every hour |
| Someone hides an instruction in an email or message (prompt injection) | Medium | Every send needs approval; agents treat messages as data |
| Changes to Claude Code break the setup | Medium | State lives in Drive and plain files; parts can be swapped |
| Ultra usage runs out | Unknown until measured | Run triage on a capped API key; check less often |
| The local filter misses sensitive content | Low, because the chat lists come first | The chat lists are the main control; the filter is a second layer |

**Open questions**

- [ ] Has the company turned on SSL VPN (OpenVPN) for the owner's user? Is its IT team comfortable with a cloud server connecting in?
- [ ] For the early period: rent a Mac mini now, or wait for the home Mac?
- [ ] Which chats go on the continuous list, which go on the searchable list, and which are blocked? What is the first version of the routing map?
- [ ] Can the system read the WhatsApp Desktop database on the owner's version of WhatsApp?
- [ ] Is macOS OCR good enough for the owner's languages?
- [ ] The chief of staff will start Claude Code sessions. Do these show up on the owner's phone through Remote Control?
- [ ] Herdr: try it once the core works, or skip it?
- [ ] Join the Claude Duet waitlist as an extra?
- [ ] Should mail and Slack from an employer with its own Claude account stay out of the system entirely? For now they stay out.

## Build phases

The build has six phases. Each phase ends with a test. The next phase starts only after the test passes.

1. **Foundations.** Rent the server, and the early-period Mac if chosen. Encrypt the disks. Install Tailscale, Claude Code and the supervisor. *Done when:* the chief of staff runs as a session that never stops, with Remote Control on. It survives a reboot, and the owner can reach it from a phone.
2. **Coordination.** The chief of staff starts a lead session and sends it a message, and the lead replies. status.md works in Drive, and the inbox works on the bus. The Cowork watchdog runs. The routing map, the one-line log and the owner's single queue all work. A regular nudge fires on schedule. The control service and the apps run. *Done when:* a test task goes from the chief of staff to a lead and back with no help. The owner approves a queue item from the iPhone, and starts and messages a lead from the Mac.
3. **Email, Telegram and approvals.** Build the watcher for Gmail, IMAP and Telegram. Add the local triage model with its filter for sensitive content. Add the Telegram bot for approvals. *Done when:* a real email produces a draft on the owner's phone within a minute, and a reply of "send" sends it.
4. **Archive and search.** Import the old messages from the Telegram and email chats on the continuous and searchable lists. Add local embeddings and the search tool with its access rules. Add search at the source, on request, for chats on no list. *Done when:* a question like "how did we apply for the visa" returns the right messages from a test chat in under a second.
5. **Mac channels.** Read iMessage and WhatsApp from the Mac databases. Import the iPhone backup. Send through the Mac app after approval. Add the screenshot backup. *Done when:* a WhatsApp message produces a draft, and a reply of "send" sends it.
6. **Extras.** Add the company VPN, Slack, browser tasks through the home exit node, voice calls, the local privacy filter, and optionally Herdr. *Done when:* each one works on one real task.

**When it is all done.** The owner gets a brief each morning. Live Telegram alerts arrive for anything important, on every channel. The owner approves replies with one word and can talk to any lead directly from a phone or a laptop. Any agent can search the owner's full history in a second. No chat outside the continuous and searchable lists reaches a model, unless the owner names it.
