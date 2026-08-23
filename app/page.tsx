'use client'

import { FormEvent, useEffect, useMemo, useRef, useState } from 'react'
import { supabaseBrowser } from '../lib/supabase-browser'

const supabase = supabaseBrowser()
const FALLBACK_COLLEGE = process.env.NEXT_PUBLIC_COLLEGE_NAME || 'Your College'
const FALLBACK_DOMAIN = process.env.NEXT_PUBLIC_COLLEGE_EMAIL_DOMAIN || ''

const ENERGY = ['Quiet Romantic', 'Main Character', 'Dance Machine', 'Chaos Coordinator', 'Lowkey', 'Memory Collector', 'Figure out yourself']
const ENERGY_DESCRIPTIONS: Record<string, string> = {
  'Quiet Romantic': 'Soft moments, meaningful conversation, and a little magic away from the crowd.',
  'Main Character': 'You want a memorable night with big energy, bold moments, and a story worth retelling.',
  'Dance Machine': 'The dance floor is your natural habitat. Music on, worries off.',
  'Chaos Coordinator': 'You bring spontaneous plans, unexpected fun, and somehow make it all work.',
  'Lowkey': 'Small circles, relaxed vibes, and a Prom night that feels comfortable rather than loud.',
  'Memory Collector': 'You care about capturing little moments and turning the night into lasting memories.',
  'Figure out yourself': 'You are still discovering your Prom vibe, and that is part of the fun.'
}
const GENDERS = ['boy', 'girl', 'gay'] as const
type Gender = typeof GENDERS[number]
const PROM_STYLES = ['Dance all night', 'Dinner + conversation', 'Photos everywhere', 'Just vibe', 'Meet new people', 'I have no plan']
const LOOKING = ['Prom +1', 'New friends', 'A great conversation', 'Prom crew', 'Just exploring']
const COURSES = ['Management', 'Sociology', 'Entrepreneurship', 'Philosophy', 'Design', 'Makerspace', 'NOTA']
const BRANCHES = ['Computer Science', 'Electrical Engineering', 'Mechanical Engineering', 'Civil Engineering', 'Chemical Engineering', 'Aerospace Engineering', 'Metallurgical & Materials', 'Engineering Physics', 'Environmental Engineering', 'Mathematics', 'Applied Geophysics', 'Chemistry', 'IEOR', 'Economics']

type BlindOption = { label: string; correct: boolean }
type BlindQuestion = { prompt: string; options: BlindOption[] }
type BlindRoundQuestion = { id: string; prompt: string; options: string[] }
type OwnedBlindQuestion = { id: string; prompt: string; options: BlindOption[]; active: boolean; sort_order: number }

type Profile = {
  id: string; name: string; email?: string | null; college_name: string; email_verified?: boolean; age?: number | null; course?: string | null
  pronouns?: string | null; branch?: string | null; year?: string | null; bio?: string | null; avatar_url?: string | null
  interests?: string[]; interests_private?: boolean; banned_at?: string | null; prom_energy?: string | null; prom_style?: string | null; looking_for?: string | null; gender?: Gender | null
}
type Match = { id: string; requester_id: string; receiver_id: string; status: string; created_at: string; requester: Profile; receiver: Profile }
type Message = { id: string; conversation_id: string; sender_id: string; body: string; created_at: string }
type Notification = { id: string; user_id: string; type: string; title: string; body: string; related_id?: string | null; read_at?: string | null; created_at: string }
type Report = { id: string; reporter_id: string; reported_id: string; reason: string; details?: string | null; status: string; created_at: string; reporter?: Profile; reported?: Profile }
type Mission = { id: string; title: string; description: string; icon: string; reward_xp: number; active: boolean; sort_order: number; min_level?: number; is_daily?: boolean }
type Completion = { id: string; mission_id: string; user_id: string; proof?: string | null; status?: 'pending'|'verified'|'rejected'; completed_at: string; completion_date?: string }
type MissionReview = Completion & { mission?: Mission; student?: Profile }

type Progress = { user_id: string; xp: number; level: number; title: string; updated_at: string }
type XPTransaction = { id: string; amount: number; source: string; created_at: string; mission_id?: string | null }
type Badge = { id: string; slug: string; name: string; description: string; icon: string }

const LEVELS = [
  { level: 1, min: 0, title: 'Newcomer 💫', unlock: 'Your Prom Pulse journey begins.' },
  { level: 2, min: 100, title: 'Social Spark ✨', unlock: 'Unlock an extra Prom Pick.' },
  { level: 3, min: 250, title: 'Vibe Finder 🎧', unlock: 'Better chemistry recommendations.' },
  { level: 4, min: 450, title: 'Connection Maker 💗', unlock: 'Unlock your first Secret Crush slot.' },
  { level: 5, min: 700, title: 'Prom Explorer 🪩', unlock: 'Unlock a special profile frame.' },
  { level: 6, min: 1000, title: 'Chemistry Hunter 🔥', unlock: 'Unlock a 60-sec Match priority badge.' },
  { level: 7, min: 1400, title: 'Heartbreaker 💘', unlock: 'Unlock an exclusive profile badge.' },
  { level: 8, min: 1800, title: 'Prom Icon 👑', unlock: 'Unlock a premium heart aura.' },
  { level: 9, min: 2250, title: 'Main Character 🌟', unlock: 'Unlock a cinematic profile treatment.' },
  { level: 10, min: 2750, title: 'Prom Legend 💎', unlock: 'Permanent Prom Legend status.' },
]

function levelForXp(xp: number) {
  let current = LEVELS[0]
  for (const level of LEVELS) if (xp >= level.min) current = level
  return current
}
function nextLevelForXp(xp: number) { return LEVELS.find(x => x.min > xp) || null }

type Memory = { id: string; user_id: string; title: string; body?: string | null; image_url?: string | null; event_kind: string; created_at: string }
type Config = { college_name: string; email_domain?: string | null; prom_date: string; prom_title: string; allow_join: boolean }

type FormState = {
  name: string; age: string; course: string; branch: string; year: string; pronouns: string; bio: string; interests: string; interests_private: boolean
  prom_energy: string; prom_style: string; looking_for: string; college_name: string; gender: Gender | ''
}
const emptyForm: FormState = { name: '', age: '', course: '', branch: '', year: '1st year', pronouns: '', bio: '', interests: '', interests_private: false, prom_energy: ENERGY[0], prom_style: PROM_STYLES[0], looking_for: LOOKING[0], college_name: FALLBACK_COLLEGE, gender: '' }

export default function Home() {
  const [session, setSession] = useState<any>(null)
  const [profile, setProfile] = useState<Profile | null>(null)
  const [config, setConfig] = useState<Config>({ college_name: FALLBACK_COLLEGE, email_domain: FALLBACK_DOMAIN, prom_date: '2026-09-05T19:00:00+05:30', prom_title: "PROM '26", allow_join: true })
  const [mode, setMode] = useState<'login'|'signup'>('signup')
  const [auth, setAuth] = useState({ email: '', password: '', otp: '' })
  const [authStep, setAuthStep] = useState<'email'|'otp'>('email')
  const otpVerifyInFlight = useRef(false)
  const [resendBusy, setResendBusy] = useState(false)
  const [resendCooldown, setResendCooldown] = useState(0)
  const [resendStatus, setResendStatus] = useState('')
  const OTP_MIN_LENGTH = 8
  const OTP_MAX_LENGTH = 8
  const [form, setForm] = useState<FormState>(emptyForm)
  const [people, setPeople] = useState<Profile[]>([])
  const [incoming, setIncoming] = useState<Match[]>([])
  const [outgoing, setOutgoing] = useState<Match[]>([])
  const [activeMatch, setActiveMatch] = useState<Match | null>(null)
  const [messages, setMessages] = useState<Message[]>([])
  const [draft, setDraft] = useState('')
  const [notifications, setNotifications] = useState<Notification[]>([])
  const [missions, setMissions] = useState<Mission[]>([])
  const [completions, setCompletions] = useState<Completion[]>([])
  const [memories, setMemories] = useState<Memory[]>([])
  const [picks, setPicks] = useState<Profile[]>([])
  const [loading, setLoading] = useState(false)
  const [toast, setToast] = useState('')
  const [tab, setTab] = useState<'home'|'discover'|'requests'|'chats'|'blind'|'missions'|'journey'|'memories'|'notifications'|'profile'|'questions'|'admin'>('home')
  const [search, setSearch] = useState('')
  const [branchFilter, setBranchFilter] = useState('all')
  const [courseFilter, setCourseFilter] = useState('all')
  const [ageFilter, setAgeFilter] = useState('all')
  const [energyFilter, setEnergyFilter] = useState('all')
  const [photoFile, setPhotoFile] = useState<File | null>(null)
  const [isAdmin, setIsAdmin] = useState(false)
  const [reports, setReports] = useState<Report[]>([])
  const [adminSearch, setAdminSearch] = useState('')
  const [onlineIds, setOnlineIds] = useState<string[]>([])
  const [unreadByConversation, setUnreadByConversation] = useState<Record<string, number>>({})
  const [crushIds, setCrushIds] = useState<string[]>([])
  const [blindTarget, setBlindTarget] = useState<Profile | null>(null)
  const [missionCompleteInfo, setMissionCompleteInfo] = useState<{ title: string; description: string; xp: number; levelUp?: boolean; newLevel?: number } | null>(null)
  const [progress, setProgress] = useState<Progress | null>(null)
  const [xpHistory, setXpHistory] = useState<XPTransaction[]>([])
  const [badges, setBadges] = useState<Badge[]>([])
  const [activeTabForJourney, setActiveTabForJourney] = useState<'progress'|'badges'|'history'>('progress')
  const [blindQuestions, setBlindQuestions] = useState<BlindRoundQuestion[]>([])
  const [blindAnswers, setBlindAnswers] = useState<number[]>([])
  const [blindSeconds, setBlindSeconds] = useState(60)
  const [blindExpiresAt, setBlindExpiresAt] = useState<string | null>(null)
  const [blindFailed, setBlindFailed] = useState(false)
  const [blindSorryPopup, setBlindSorryPopup] = useState(false)
  const [showBlindReveal, setShowBlindReveal] = useState(false)
  const [blindRoundId, setBlindRoundId] = useState<string | null>(null)
  const [myBlindQuestions, setMyBlindQuestions] = useState<OwnedBlindQuestion[]>([])
  const [questionDraft, setQuestionDraft] = useState<{ id?: string; prompt: string; options: string[]; correctIndex: number }>({ prompt: '', options: ['', '', '', ''], correctIndex: 0 })
  const [secretMatchPopup, setSecretMatchPopup] = useState<{ name?: string } | null>(null)
  const [secretCrushIntroOpen, setSecretCrushIntroOpen] = useState(false)
  const [unmatchConfirm, setUnmatchConfirm] = useState<Match | null>(null)
  const [lastSecretMatchNotificationId, setLastSecretMatchNotificationId] = useState<string | null>(null)
  const [blockWithReport, setBlockWithReport] = useState(false)
  const [missionTarget, setMissionTarget] = useState<Mission | null>(null)
  const [missionProof, setMissionProof] = useState('')
  const [memoryTitle, setMemoryTitle] = useState('')
  const [memoryBody, setMemoryBody] = useState('')
  const [reportTarget, setReportTarget] = useState<Profile | null>(null)
  const [reportReason, setReportReason] = useState('')
  const [reportDetails, setReportDetails] = useState('')

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session))
    const { data: listener } = supabase.auth.onAuthStateChange((_event, current) => setSession(current))
    supabase.from('college_config').select('*').eq('id', true).maybeSingle().then(({ data }) => { if (data) setConfig(data as Config) })
    return () => listener.subscription.unsubscribe()
  }, [])

  useEffect(() => {
    if (session?.user) loadApp(session.user.id)
  }, [session])

  useEffect(() => {
    if (!session?.user) return
    const presence = supabase.channel('campus-presence', { config: { presence: { key: session.user.id } } })
    const sync = () => setOnlineIds(Object.keys(presence.presenceState()))
    presence.on('presence', { event: 'sync' }, sync).on('presence', { event: 'join' }, sync).on('presence', { event: 'leave' }, sync)
      .subscribe(async status => {
        if (status === 'SUBSCRIBED') {
          await presence.track({ online_at: new Date().toISOString() })
          await supabase.from('profiles').update({ last_seen_at: new Date().toISOString() }).eq('id', session.user.id)
        }
      })
    return () => { supabase.removeChannel(presence) }
  }, [session])

  useEffect(() => {
    if (!session?.user) return
    const channel = supabase.channel(`user-events-${session.user.id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'match_requests' }, async () => { await refreshMatches(session.user.id); await loadPeople(session.user.id, profile?.college_name || config.college_name) })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'notifications', filter: `user_id=eq.${session.user.id}` }, async payload => {
        await loadNotifications(session.user.id)
        const n = payload.new as Notification
        if (payload.eventType === 'INSERT' && n.type === 'secret_match' && n.id !== lastSecretMatchNotificationId) {
          setLastSecretMatchNotificationId(n.id)
          setSecretMatchPopup({})
        }
      })
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages' }, payload => {
        const msg = payload.new as Message
        if (msg.sender_id !== session.user.id && msg.conversation_id !== activeMatch?.id) setUnreadByConversation(prev => ({ ...prev, [msg.conversation_id]: (prev[msg.conversation_id] || 0) + 1 }))
      })
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'secret_crushes' }, () => loadCrushes(session.user.id))
      .subscribe()
    return () => { supabase.removeChannel(channel) }
  }, [session, activeMatch?.id])

  useEffect(() => {
    if (!activeMatch) return
    supabase.from('messages').select('*').eq('conversation_id', activeMatch.id).order('created_at', { ascending: true }).then(({ data }) => setMessages((data as Message[]) || []))
    markConversationRead(activeMatch.id)
    const channel = supabase.channel(`conversation-${activeMatch.id}`).on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages', filter: `conversation_id=eq.${activeMatch.id}` }, async payload => {
      const msg = payload.new as Message
      setMessages(prev => prev.some(x => x.id === msg.id) ? prev : [...prev, msg])
      await markConversationRead(activeMatch.id)
    }).subscribe()
    return () => { supabase.removeChannel(channel) }
  }, [activeMatch?.id])

  async function loadApp(userId: string) {
    // Ensure the full mission catalog exists before loading it. The RPC is a security-definer
    // function so normal users never need direct INSERT access to prom_missions.
    await supabase.rpc('ensure_prom_mission_catalog')
    const [{ data: p }, { data: c }, { data: missionRows }, { data: completionRows }, { data: progressRow }, { data: xpRows }, { data: badgeRows }] = await Promise.all([
      supabase.from('profiles').select('*').eq('id', userId).maybeSingle(),
      supabase.from('college_config').select('*').eq('id', true).maybeSingle(),
      supabase.from('prom_missions').select('*').eq('active', true).order('sort_order'),
      supabase.from('mission_completions').select('*').eq('user_id', userId).order('completed_at', { ascending: false }),
      supabase.from('user_progress').select('*').eq('user_id', userId).maybeSingle(),
      supabase.from('xp_transactions').select('id, amount, source, created_at, mission_id').eq('user_id', userId).order('created_at', { ascending: false }).limit(80),
      supabase.from('user_badges').select('badge:badges(*)').eq('user_id', userId).order('earned_at', { ascending: false }),
    ])
    if (c) setConfig(c as Config)
    if (missionRows) setMissions(missionRows as Mission[])
    if (completionRows) setCompletions(completionRows as Completion[])
    if (progressRow) setProgress(progressRow as Progress)
    if (xpRows) setXpHistory(xpRows as XPTransaction[])
    if (badgeRows) setBadges((badgeRows || []).map((x:any) => x.badge).filter(Boolean) as Badge[])
    if (p) {
      setProfile(p as Profile)
      setForm({
        name: p.name || '', age: p.age?.toString() || '', course: p.course || '', branch: p.branch || '', year: p.year || '1st year', pronouns: p.pronouns || '', bio: p.bio || '', interests: (p.interests || []).join(', '),
        prom_energy: p.prom_energy || ENERGY[0], prom_style: p.prom_style || PROM_STYLES[0], looking_for: p.looking_for || LOOKING[0], college_name: p.college_name || FALLBACK_COLLEGE, interests_private: !!p.interests_private, gender: (p.gender || '') as Gender | '',
      })
    }
    await Promise.all([loadPeople(userId, p?.college_name || config.college_name), refreshMatches(userId), loadNotifications(userId), loadCrushes(userId), loadMemories(userId), loadBlindQuestionBank(userId), checkAdmin(userId)])
  }

  async function loadPeople(userId = session?.user?.id, collegeName?: string) {
    if (!userId) return
    // Discovery uses the privacy-safe view. It never returns private interests,
    // email addresses, or other account-only fields.
    const { data, error } = await supabase.from('public_profile_discovery').select('*')
      .eq('college_name', collegeName || profile?.college_name || config.college_name)
      .neq('id', userId)
      .order('created_at', { ascending: false })
      .limit(400)
    if (error) {
      flash(`Discovery failed: ${error.message}`)
      setPeople([])
      return
    }
    setPeople((data as Profile[]) || [])
  }

  async function refreshMatches(userId = session?.user?.id) {
    if (!userId) return
    const [{ data: inc }, { data: out }] = await Promise.all([
      supabase.from('match_requests').select('*, requester:profiles!match_requests_requester_id_fkey(*), receiver:profiles!match_requests_receiver_id_fkey(*)').eq('receiver_id', userId).order('created_at', { ascending: false }),
      supabase.from('match_requests').select('*, requester:profiles!match_requests_requester_id_fkey(*), receiver:profiles!match_requests_receiver_id_fkey(*)').eq('requester_id', userId).order('created_at', { ascending: false }),
    ])
    const incomingRows = (inc as Match[]) || []
    const outgoingRows = (out as Match[]) || []

    // Collapse accidental reverse-direction duplicates into one relationship per person pair.
    // Preference: accepted > pending > declined, then newest row.
    const priority: Record<string, number> = { accepted: 5, pending: 4, cancelled: 3, declined: 2 }
    const byPerson = new Map<string, Match>()
    ;[...incomingRows, ...outgoingRows].forEach(row => {
      const otherId = row.requester_id === userId ? row.receiver_id : row.requester_id
      const existing = byPerson.get(otherId)
      if (!existing) return byPerson.set(otherId, row)
      const a = priority[row.status] || 0
      const b = priority[existing.status] || 0
      if (a > b || (a === b && new Date(row.created_at).getTime() > new Date(existing.created_at).getTime())) {
        byPerson.set(otherId, row)
      }
    })

    const collapsed = [...byPerson.values()]
    // Keep accepted relationships in both directions. The Requests tab filters to pending,
    // while Chats needs accepted rows whether the current user was requester or receiver.
    setIncoming(collapsed.filter(r => r.receiver_id === userId))
    setOutgoing(collapsed.filter(r => r.requester_id === userId))
  }

  async function loadNotifications(userId: string) {
    const { data } = await supabase.from('notifications').select('*').eq('user_id', userId).order('created_at', { ascending: false }).limit(80)
    setNotifications((data as Notification[]) || [])
  }

  async function loadCrushes(userId: string) {
    const { data } = await supabase.from('secret_crushes').select('to_user_id').eq('from_user_id', userId)
    setCrushIds((data || []).map(x => x.to_user_id))
  }

  async function loadBlindQuestionBank(userId: string) {
    // Backfill the default question bank for accounts created before Blind Match was added.
    const { error: ensureError } = await supabase.rpc('ensure_blind_questions', { target_user_id: userId })
    if (ensureError) { flash(`Question bank setup failed: ${ensureError.message}`); return }
    const { data, error } = await supabase.from('blind_questions').select('*').eq('user_id', userId).eq('active', true).order('sort_order', { ascending: true })
    if (!error) setMyBlindQuestions((data as OwnedBlindQuestion[]) || [])
  }

  async function loadMemories(userId: string) {
    const { data } = await supabase.from('memories').select('*').eq('user_id', userId).order('created_at', { ascending: false })
    setMemories((data as Memory[]) || [])
  }

  async function checkAdmin(userId: string) {
    const { data } = await supabase.from('admin_users').select('user_id').eq('user_id', userId).maybeSingle()
    setIsAdmin(!!data)
  }

  async function loadReports() {
    if (!isAdmin) return
    const { data } = await supabase.from('reports').select('*, reporter:profiles!reports_reporter_id_fkey(*), reported:profiles!reports_reported_id_fkey(*)').order('created_at', { ascending: false }).limit(100)
    setReports((data as Report[]) || [])
  }
  useEffect(() => { if (isAdmin && tab === 'admin') loadReports() }, [isAdmin, tab])

  const accepted = useMemo(() => {
    const map = new Map<string, Match>()
    ;[...incoming, ...outgoing].filter(x => x.status === 'accepted').forEach(x => {
      const otherId = x.requester_id === session?.user?.id ? x.receiver_id : x.requester_id
      if (!map.has(otherId)) map.set(otherId, x)
    })
    return [...map.values()]
  }, [incoming, outgoing, session?.user?.id])
  const pendingIncoming = incoming.filter(x => x.status === 'pending')
  const unreadNotifications = notifications.filter(x => !x.read_at).length
  const currentOther = (m: Match) => m.requester_id === session?.user?.id ? m.receiver : m.requester

  const filters = useMemo(() => ({ branches: BRANCHES.slice(), courses: COURSES.slice() }), [])

  const filteredPeople = useMemo(() => {
    const q = search.trim().toLowerCase().replace(/\s+/g, ' ')
    return people.filter(p => {
      const searchMatch = !q || [p.name, p.course, p.branch, p.bio, ...(p.interests || []), p.prom_energy, p.prom_style].filter(Boolean).some(v => String(v).toLowerCase().includes(q))
      const branchMatch = branchFilter === 'all' || p.branch === branchFilter
      const courseMatch = courseFilter === 'all' || p.course === courseFilter
      const energyMatch = energyFilter === 'all' || p.prom_energy === energyFilter
      const ageMatch = ageFilter === 'all' || (ageFilter === '18-19' && (p.age || 0) >= 18 && (p.age || 0) <= 19) || (ageFilter === '20-21' && (p.age || 0) >= 20 && (p.age || 0) <= 21) || (ageFilter === '22+' && (p.age || 0) >= 22)
      return searchMatch && branchMatch && courseMatch && energyMatch && ageMatch
    })
  }, [people, search, branchFilter, courseFilter, ageFilter, energyFilter])

  const chemistry = (p: Profile) => {
    const mine = new Set(profile?.interests_private ? [] : (profile?.interests || []).map(x => x.toLowerCase()))
    const theirs = p.interests_private ? 0 : (p.interests || []).filter(x => mine.has(x.toLowerCase())).length
    const base = 58 + Math.min(theirs * 8, 24)
    if (profile?.prom_energy && p.prom_energy === profile.prom_energy) return Math.min(base + 10, 98)
    return Math.min(base, 92)
  }

  useEffect(() => {
    if (!profile || people.length === 0) return
    const dayKey = new Date().toISOString().slice(0, 10)
    const dailyScore = (p: Profile) => {
      const seed = `${dayKey}:${p.id}`
      let hash = 0
      for (let i = 0; i < seed.length; i++) hash = (hash * 31 + seed.charCodeAt(i)) >>> 0
      return hash
    }
    const picksForToday = [...people]
      .sort((a, b) => chemistry(b) - chemistry(a) || dailyScore(a) - dailyScore(b))
      .slice(0, 3)
    setPicks(picksForToday)
  }, [profile?.id, people.length, search])

  const [tick, setTick] = useState(Date.now())
  useEffect(() => { const i = setInterval(() => setTick(Date.now()), 1000); return () => clearInterval(i) }, [])

  const countdown = useMemo(() => {
    const target = new Date(config.prom_date).getTime()
    const delta = target - tick
    if (delta <= 0) return { live: true, days: 0, hours: 0, mins: 0, secs: 0 }
    return { live: false, days: Math.floor(delta / 86400000), hours: Math.floor((delta % 86400000) / 3600000), mins: Math.floor((delta % 3600000) / 60000), secs: Math.floor((delta % 60000) / 1000) }
  }, [config.prom_date, tick])

  useEffect(() => {
    if (resendCooldown <= 0) return
    const id = window.setInterval(() => {
      setResendCooldown(v => Math.max(0, v - 1))
    }, 1000)
    return () => window.clearInterval(id)
  }, [resendCooldown])

  function flash(message: string) { setToast(message); setTimeout(() => setToast(''), 2800) }

  async function authSubmit(e: FormEvent) {
    e.preventDefault()
    if (loading) return
    setLoading(true)

    // Signup: password is set once, then the email is verified by OTP.
    if (mode === 'signup') {
      if (authStep === 'otp') {
        if (otpVerifyInFlight.current) { setLoading(false); return }
        const email = auth.email.trim().toLowerCase()
        const token = auth.otp.replace(/\D/g, '').slice(0, OTP_MAX_LENGTH)
        if (token.length < OTP_MIN_LENGTH || token.length > OTP_MAX_LENGTH) {
          flash(`Enter the 8-digit code from your latest email.`)
          setLoading(false)
          return
        }
        otpVerifyInFlight.current = true
        try {
          const { data, error } = await supabase.auth.verifyOtp({ email, token, type: 'signup' })
          if (error) {
            if (error.status === 403 || /expired|invalid/i.test(error.message)) {
              flash('That code is invalid or expired. Use the latest code or resend a new one.')
            } else {
              flash(error.message)
            }
          } else {
            // Profile creation/finalization happens only after Supabase confirms the OTP.
            // This keeps an unverified signup out of the application and avoids trusting
            // a client-side email_verified flag.
            const finalize = await supabase.rpc('finalize_signup_profile')
            if (finalize.error) {
              flash(`Email verified, but profile setup failed: ${finalize.error.message}`)
              setLoading(false)
              return
            }
            const genderUpdate = await supabase.from('profiles').update({ gender: form.gender || null }).eq('id', data.user?.id || '').select('id').maybeSingle()
            if (genderUpdate.error || !form.gender) {
              flash(genderUpdate.error?.message || 'Choose your gender before entering Prom Pulse.')
              setLoading(false)
              return
            }

            let verifiedSession = data.session
            if (!verifiedSession) {
              const login = await supabase.auth.signInWithPassword({
                email,
                password: auth.password,
              })
              if (login.error || !login.data.session) {
                flash(login.error?.message || 'Email verified. Please log in with your password.')
                setAuthStep('email')
                setAuth(prev => ({ ...prev, otp: '' }))
                return
              }
              verifiedSession = login.data.session
            }

            setSession(verifiedSession)
            setSecretCrushIntroOpen(true)
            setAuthStep('email')
            setAuth(prev => ({ ...prev, otp: '' }))
            flash('Email verified. Welcome to Prom Pulse 💗')
          }
        } finally {
          otpVerifyInFlight.current = false
          setLoading(false)
        }
        return
      }

      if (auth.password.length < 8) {
        flash('Use a password with at least 8 characters.')
        setLoading(false)
        return
      }

      const metadata = { name: form.name, age: form.age, course: form.course, branch: form.branch, year: form.year, pronouns: form.pronouns, bio: form.bio, interests: form.interests.split(',').map(x => x.trim()).filter(Boolean), interests_private: form.interests_private, prom_energy: form.prom_energy, prom_style: form.prom_style, looking_for: form.looking_for, gender: form.gender || null }
      const { data, error } = await supabase.auth.signUp({
        email: auth.email.trim(),
        password: auth.password,
        options: { data: metadata },
      })
      if (error) {
        flash(error.message)
      } else if (data.session) {
        // Supabase only returns a session immediately when email confirmation is disabled.
        // Prom Pulse requires one-time email verification during signup, so do not let an
        // unverified account enter the app. Sign the session out and ask the owner/admin
        // to enable "Confirm email" in Supabase Authentication settings.
        await supabase.auth.signOut()
        flash('Email OTP is not enabled on this Supabase project. Turn on Authentication → Email → Confirm email, then try signup again.')
      } else {
        setAuthStep('otp')
        flash(`We sent a one-time verification code to ${auth.email.trim()}. Use the newest code from your inbox.`)
      }
      setLoading(false)
      return
    }

    // Login: password only. OTP is not requested again.
    if (auth.password.length < 8) {
      flash('Enter your password.')
      setLoading(false)
      return
    }
    const { data, error } = await supabase.auth.signInWithPassword({
      email: auth.email.trim(),
      password: auth.password,
    })
    if (error) flash(error.message)
    else {
      setSession(data.session)
      setSecretCrushIntroOpen(true)
      flash('Welcome back to Prom Pulse 💗')
    }
    setLoading(false)
  }

  async function resendOtp() {
    if (mode !== 'signup' || authStep !== 'otp') return
    const email = auth.email.trim().toLowerCase()
    if (!email) { setResendStatus('Enter your email first.'); return }
    if (resendBusy || resendCooldown > 0) return
    setResendBusy(true)
    setResendStatus('Sending a new 8-digit code…')
    try {
      const { error } = await supabase.auth.resend({ type: 'signup', email })
      if (error) {
        setResendStatus(`Resend failed: ${error.message}`)
        flash(`Resend failed: ${error.message}`)
        return
      }
      setAuth(prev => ({ ...prev, otp: '' }))
      setResendCooldown(60)
      setResendStatus('New code sent. Use the newest email code only.')
      flash('New 8-digit verification code sent.')
    } catch (err: any) {
      const message = err?.message || 'Unable to resend the code.'
      setResendStatus(`Resend failed: ${message}`)
      flash(`Resend failed: ${message}`)
    } finally {
      setResendBusy(false)
    }
  }

  async function signOut() { await supabase.auth.signOut(); setSession(null); setProfile(null); setTab('home') }

  async function deleteAccount() {
    if (!session?.user) return
    const confirmed = window.confirm('Permanently delete your Prom Pulse account? This will remove your profile, matches, messages, memories, XP, badges, crushes and all other account data. This cannot be undone.')
    if (!confirmed) return
    setLoading(true)
    try {
      // Delete avatar objects via the Supabase Storage API before deleting the
      // account. Supabase does not allow direct SQL writes to storage.objects.
      const folder = session.user.id
      const { data: avatarFiles, error: listError } = await supabase.storage.from('avatars').list(folder, { limit: 100 })
      if (listError) throw listError
      if (avatarFiles?.length) {
        const paths = avatarFiles.map(file => `${folder}/${file.name}`)
        const { error: removeError } = await supabase.storage.from('avatars').remove(paths)
        if (removeError) throw removeError
      }

      const { error } = await supabase.rpc('delete_my_account')
      if (error) throw error

      await supabase.auth.signOut()
      setSession(null)
      setProfile(null)
      setTab('home')
      setForm(emptyForm)
      flash('Your account has been permanently deleted.')
    } catch (error: any) {
      flash(error?.message || 'Unable to delete your account. No account deletion was completed.')
    } finally {
      setLoading(false)
    }
  }

  async function saveProfile(e: FormEvent) {
    e.preventDefault(); if (!session?.user) return; setLoading(true)
    const payload = { name: form.name, age: Number(form.age) || null, course: form.course || null, branch: form.branch || null, year: form.year, pronouns: form.pronouns || null, bio: form.bio || null, interests: form.interests.split(',').map(x=>x.trim()).filter(Boolean), interests_private: !!form.interests_private, prom_energy: form.prom_energy, prom_style: form.prom_style, looking_for: form.looking_for, gender: form.gender || null }
    const { error } = await supabase.from('profiles').update(payload).eq('id', session.user.id)
    if (error) {
      flash(error.message)
    } else {
      // Do not chain .select().single() onto the UPDATE. A profile can be
      // successfully updated even when a restrictive discovery SELECT policy
      // prevents PostgREST from returning the updated row.
      setProfile(prev => prev ? ({ ...prev, ...payload }) as Profile : prev)
      flash('Profile saved ✨')
      await loadPeople(session.user.id)
    }
    setLoading(false)
  }

  async function uploadPhoto() {
    if (!photoFile || !session?.user) return
    setLoading(true)
    const ext = photoFile.name.split('.').pop() || 'jpg'
    const path = `${session.user.id}/avatar-${Date.now()}.${ext}`
    const { error: upErr } = await supabase.storage.from('avatars').upload(path, photoFile, { upsert: true })
    if (upErr) flash(upErr.message)
    else {
      const { data } = supabase.storage.from('avatars').getPublicUrl(path)
      await supabase.from('profiles').update({ avatar_url: data.publicUrl }).eq('id', session.user.id)
      setProfile(prev => prev ? ({ ...prev, avatar_url: data.publicUrl }) : prev); flash('Photo updated 💗'); setPhotoFile(null)
    }
    setLoading(false)
  }

  function relationshipWith(id: string) {
    const all = [...incoming, ...outgoing].filter(m => m.requester_id === id || m.receiver_id === id)
    const accepted = all.find(m => m.status === 'accepted')
    if (accepted) return { status: 'accepted' as const, match: accepted }
    const incomingPending = all.find(m => m.receiver_id === session?.user?.id && m.requester_id === id && m.status === 'pending')
    if (incomingPending) return { status: 'incoming' as const, match: incomingPending }
    const outgoingPending = all.find(m => m.requester_id === session?.user?.id && m.receiver_id === id && m.status === 'pending')
    if (outgoingPending) return { status: 'pending' as const, match: outgoingPending }
    const cancelled = all.find(m => m.status === 'cancelled')
    if (cancelled) return { status: 'none' as const, match: null }
    const declined = all.find(m => m.status === 'declined')
    if (declined) return { status: 'declined' as const, match: declined }
    return { status: 'none' as const, match: null }
  }

  async function requestPartner(id: string) {
    if (!session?.user || id === session.user.id) return
    const relation = relationshipWith(id)
    if (relation.status === 'accepted') { flash('You already matched 💗'); return }
    if (relation.status === 'pending') { flash('Prom request already sent 💌'); return }
    if (relation.status === 'incoming' && relation.match) {
      await respond(relation.match.id, 'accepted')
      return
    }
    if (relation.status === 'declined') { flash('That request was declined. You cannot send another request to the same person.'); return }
    setLoading(true)
    const { error } = await supabase.rpc('send_prom_request', { target_user_id: id })
    if (error) flash(error.message); else { flash('Prom request sent 💌'); await refreshMatches() }
    setLoading(false)
  }

  async function respond(id: string, status: 'accepted'|'declined') {
    setLoading(true)
    const { error } = await supabase.rpc('respond_prom_request', { request_uuid: id, new_status: status })
    if (error) flash(error.message); else { flash(status === 'accepted' ? 'You have a Prom +1 ✨' : 'Request declined'); await refreshMatches(); if (status === 'accepted') await loadPeople(session?.user?.id, profile?.college_name || config.college_name) }
    setLoading(false)
  }

  async function unmatch(match: Match) {
    if (!session?.user) return
    setLoading(true)
    const { error } = await supabase.rpc('unmatch_prom', { request_uuid: match.id })
    if (error) { flash(error.message) }
    else {
      setActiveMatch(null)
      setUnmatchConfirm(null)
      flash('You are no longer matched. Your profile is visible in discovery again. 💗')
      await refreshMatches(session.user.id)
      await loadPeople(session.user.id, profile?.college_name || config.college_name)
    }
    setLoading(false)
  }

  async function sendMessage(e: FormEvent) {
    e.preventDefault(); if (!activeMatch || !draft.trim() || !session?.user) return
    const { error } = await supabase.from('messages').insert({ conversation_id: activeMatch.id, sender_id: session.user.id, body: draft.trim() })
    if (error) flash(error.message); else setDraft('')
  }

  async function markConversationRead(conversationId: string) {
    if (!session?.user) return
    await supabase.from('conversation_reads').upsert({ conversation_id: conversationId, user_id: session.user.id, last_read_at: new Date().toISOString() })
    setUnreadByConversation(prev => ({ ...prev, [conversationId]: 0 }))
  }

  async function markAllNotifications() {
    if (!session?.user) return
    await supabase.from('notifications').update({ read_at: new Date().toISOString() }).eq('user_id', session.user.id).is('read_at', null)
    loadNotifications(session.user.id)
  }

  async function secretCrush(p: Profile) {
    if (!session?.user) return
    if (crushIds.includes(p.id)) { flash('Already in your Secret Crush list 💗'); return }
    const { data, error } = await supabase.rpc('save_secret_crush', { target_user_id: p.id })
    if (error) flash(error.message)
    else {
      setCrushIds(prev => prev.includes(p.id) ? prev : [...prev, p.id])
      if (data?.status === 'mutual') { setSecretMatchPopup({ name: p.name }); await refreshMatches(); await loadNotifications(session.user.id); flash('It’s mutual. 💗') }
      else flash('Secret Crush saved. They won’t know unless they choose you too. 🤫')
    }
  }

  async function submitMissionProof(e: FormEvent) {
    e.preventDefault()
    if (!session?.user || !missionTarget || !missionProof.trim()) return
    const existingToday = completions.find(x => x.mission_id === missionTarget.id && (!x.completion_date || x.completion_date === new Date().toISOString().slice(0,10)))
    const missionIsDaily = (missionTarget as any).is_daily
    if (missionIsDaily ? existingToday : completions.some(x => x.mission_id === missionTarget.id)) {
      flash(missionIsDaily ? "You already completed today's version ✓" : 'Mission already completed ✓')
      return
    }
    setLoading(true)
    const { data, error } = await supabase.rpc('complete_prom_mission', { mission_uuid: missionTarget.id, proof_text: missionProof.trim() })
    if (error) {
      flash(error.message)
      setLoading(false)
      return
    }
    const result = (data || {}) as any
    const completion: Completion = {
      id: result.completion_id, mission_id: missionTarget.id, user_id: session.user.id, proof: missionProof.trim(), status: 'verified',
      completed_at: new Date().toISOString(), completion_date: result.completion_date || new Date().toISOString().slice(0,10)
    }
    setCompletions(prev => [completion, ...prev])
    if (result.progress) {
      setProgress(result.progress as Progress)
      // Re-fetch the mission catalog after a level-up so newly unlocked tiers
      // appear immediately without requiring a page refresh.
      const { data: freshMissions } = await supabase.from('prom_missions').select('*').eq('active', true).order('sort_order')
      if (freshMissions) setMissions(freshMissions as Mission[])
    }
    if (result.xp_transaction) setXpHistory(prev => [result.xp_transaction as XPTransaction, ...prev])
    if (result.badges) setBadges(result.badges as Badge[])
    setMissionCompleteInfo({ title: missionTarget.title, description: missionProof.trim(), xp: Number(result.xp_awarded || missionTarget.reward_xp), levelUp: !!result.level_up, newLevel: result.new_level })
    setMissionTarget(null)
    setMissionProof('')
    setLoading(false)
  }

  async function saveMemory(e: FormEvent) {
    e.preventDefault(); if (!session?.user || !memoryTitle.trim()) return
    const { data, error } = await supabase.from('memories').insert({ user_id: session.user.id, title: memoryTitle.trim(), body: memoryBody.trim() || null, event_kind: countdown.live ? 'prom-night' : 'pre-prom' }).select().single()
    if (error) flash(error.message); else { setMemories(prev => [data as Memory, ...prev]); setMemoryTitle(''); setMemoryBody(''); flash('Memory added to the vault 💗') }
  }

  async function saveBlindQuestion() {
    if (!session?.user) return
    const cleaned = questionDraft.options.map(x=>x.trim())
    if (questionDraft.prompt.trim().length < 5 || cleaned.some(x=>!x) || cleaned.length !== 4) { flash('Add a question and four answer choices.'); return }
    const options = cleaned.map((label, index) => ({ label, correct: index === questionDraft.correctIndex }))
    const payload = { prompt: questionDraft.prompt.trim(), options, active: true, sort_order: myBlindQuestions.length + (questionDraft.id ? 0 : 1) }
    const result = questionDraft.id
      ? await supabase.from('blind_questions').update(payload).eq('id', questionDraft.id).select().single()
      : await supabase.from('blind_questions').insert({ ...payload, user_id: session.user.id }).select().single()
    if (result.error) { flash(result.error.message); return }
    await loadBlindQuestionBank(session.user.id)
    setQuestionDraft({ prompt:'', options:['','','',''], correctIndex:0 })
    flash(questionDraft.id ? 'Question updated ✨' : 'Question added ✨')
  }

  async function deleteBlindQuestion(id: string) {
    const { error } = await supabase.from('blind_questions').update({ active:false }).eq('id', id).eq('user_id', session.user.id)
    if (error) flash(error.message); else { await loadBlindQuestionBank(session.user.id); flash('Question removed.'); }
  }

  async function submitReport(e: FormEvent) {
    e.preventDefault(); if (!session?.user || !reportTarget) return
    const { error } = await supabase.from('reports').insert({ reporter_id: session.user.id, reported_id: reportTarget.id, reason: reportReason || 'Other', details: reportDetails || null })
    if (error) { flash(error.message); return }
    if (blockWithReport) {
      const { error: blockError } = await supabase.rpc('block_user', { target_user_id: reportTarget.id })
      if (blockError) { flash(blockError.message); return }
    }
    flash(blockWithReport ? 'Report sent and person blocked. You can still view their profile. 🔒' : 'Report sent to the admin team.')
    setReportTarget(null); setReportReason(''); setReportDetails(''); setBlockWithReport(false)
    await loadPeople()
  }

  async function moderateReport(id: string, status: string) { await supabase.from('reports').update({ status }).eq('id', id); loadReports() }
  async function toggleBan(id: string, banned: boolean) { await supabase.from('profiles').update({ banned_at: banned ? new Date().toISOString() : null }).eq('id', id); loadReports(); loadPeople() }

  async function openBlind(p: Profile) {
    setBlindTarget(p)
    setBlindSeconds(60)
    setBlindExpiresAt(null)
    setBlindFailed(false)
    setBlindSorryPopup(false)
    setShowBlindReveal(false)
    setBlindAnswers([])
    setBlindQuestions([])
    setBlindRoundId(null)
    const { data, error } = await supabase.rpc('start_blind_round', { target_user_id: p.id })
    if (error) { flash(error.message); setBlindTarget(null); return }
    const expiresAt = data?.expires_at ? String(data.expires_at) : null
    const questions = Array.isArray(data?.questions) ? data.questions as BlindRoundQuestion[] : []
    if (!data?.round_id || !expiresAt || questions.length !== 3) {
      flash('Blind Match could not create a valid 3-question round. Please try again.')
      setBlindTarget(null)
      return
    }
    setBlindRoundId(String(data.round_id))
    setBlindExpiresAt(expiresAt)
    setBlindSeconds(Math.max(0, Math.ceil((new Date(expiresAt).getTime() - Date.now()) / 1000)))
    setBlindQuestions(questions)
    setBlindAnswers(questions.map(() => -1))
  }

  useEffect(() => {
    if (!blindTarget || !blindExpiresAt || showBlindReveal || blindFailed) return
    const tick = () => {
      const remaining = Math.max(0, Math.ceil((new Date(blindExpiresAt).getTime() - Date.now()) / 1000))
      setBlindSeconds(remaining)
      if (remaining <= 0) setBlindFailed(true)
    }
    tick()
    const timer = setInterval(tick, 250)
    return () => clearInterval(timer)
  }, [blindTarget, blindExpiresAt, showBlindReveal, blindFailed])

  async function submitBlind() {
    if (!blindTarget || !blindRoundId || loading) return
    if (blindSeconds <= 0) { setBlindFailed(true); setBlindSorryPopup(true); return }
    if (blindQuestions.length !== 3 || blindAnswers.length !== 3 || blindAnswers.some(x => !Number.isInteger(x) || x < 0)) {
      flash('Please answer all three questions first.');
      return
    }
    setLoading(true)
    try {
      const answers = blindQuestions.map((q, i) => ({ question_id: q.id, option_index: Number(blindAnswers[i]) }))
      const { data, error } = await supabase.rpc('submit_blind_round', { round_uuid: blindRoundId, answers })
      if (error) {
        console.error('submit_blind_round failed', error)
        flash(`Could not check answers: ${error.message}`)
        return
      }
      if (!data || typeof data !== 'object') {
        flash('The server returned an invalid Blind Match result. Please try again.');
        return
      }
      if (data.expired) {
        setBlindFailed(true)
        setBlindSorryPopup(true)
        flash('Time ran out. 💗')
        return
      }
      if (data.success === true) {
        setShowBlindReveal(true)
        if (data.progress) setProgress(data.progress as Progress)
        if (data.xp_transaction) setXpHistory(prev => [data.xp_transaction as XPTransaction, ...prev])
        if (data.badges) setBadges(data.badges as Badge[])
        flash('+100 XP — Speed Heart challenge completed ⏱️')
      } else {
        setBlindFailed(true)
        setBlindSorryPopup(true)
        flash(`Not quite. You got ${Number(data.score || 0)}/3. There is someone else out there for your vibe. 💗`)
      }
    } finally {
      setLoading(false)
    }
  }

  if (!session) return <AuthScreen mode={mode} setMode={setMode} auth={auth} setAuth={setAuth} form={form} setForm={setForm} submit={authSubmit} resendOtp={resendOtp} resendBusy={resendBusy} resendCooldown={resendCooldown} resendStatus={resendStatus} loading={loading} config={config} authStep={authStep} setAuthStep={setAuthStep} />

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand"><span className="brand-mark">♡</span><span>Prom <b>Pulse</b></span></div>
        <div className="college-chip"><span className="live-dot" /> {config.college_name}</div>
        <nav>
          <NavButton active={tab==='home'} onClick={()=>setTab('home')} label="Tonight" icon="✦" />
          <NavButton active={tab==='discover'} onClick={()=>setTab('discover')} label="Discover" icon="♡" />
          <NavButton active={tab==='requests'} onClick={()=>setTab('requests')} label="Requests" icon="✉" count={pendingIncoming.length} />
          <NavButton active={tab==='chats'} onClick={()=>setTab('chats')} label="Chats" icon="◌" count={Object.values(unreadByConversation).reduce((a:number,b:number)=>a+b,0)} />
          <NavButton active={tab==='blind'} onClick={()=>setTab('blind')} label="60-sec Match" icon="⏱" />
          <NavButton active={tab==='questions'} onClick={()=>setTab('questions')} label="My Questions" icon="✎" />
          <NavButton active={tab==='missions'} onClick={()=>setTab('missions')} label="Missions" icon="🎯" />
          <NavButton active={tab==='journey'} onClick={()=>setTab('journey')} label="My Prom Journey" icon="✧" />
          <NavButton active={tab==='memories'} onClick={()=>setTab('memories')} label="Memory Vault" icon="✦" />
          <NavButton active={tab==='notifications'} onClick={()=>setTab('notifications')} label="Notifications" icon="♧" count={unreadNotifications} />
          <NavButton active={tab==='profile'} onClick={()=>setTab('profile')} label="My Profile" icon="◉" />
          {isAdmin && <NavButton active={tab==='admin'} onClick={()=>setTab('admin')} label="Admin" icon="♛" />}
        </nav>
        <div className="sidebar-bottom">
          <button className="profile-mini" onClick={()=>setTab('profile')}><Avatar p={profile} size="sm" /><span><b>{profile?.name || 'Student'}</b><small>{profile?.prom_energy || 'Prom Explorer'}</small></span></button>
          <button className="logout" onClick={signOut}>Log out</button>
        </div>
      </aside>

      <main className="main-content">
        <header className="topbar"><div><span className="eyebrow">{config.prom_title}</span><h1>{countdown.live ? 'Prom Night is LIVE.' : 'Find your people before the lights go down.'}</h1></div><div className="top-actions"><button className="icon-btn" onClick={()=>setTab('notifications')}>♧{unreadNotifications>0&&<i/>}</button><button className="avatar-button" onClick={()=>setTab('profile')}><Avatar p={profile} size="sm"/></button></div></header>

        {tab==='home' && <HomeDashboard profile={profile} progress={progress} config={config} countdown={countdown} people={people} picks={picks} chemistry={chemistry} onlineIds={onlineIds} crushIds={crushIds} onDiscover={()=>setTab('discover')} onCrush={secretCrush} onRequest={requestPartner} relationshipWith={relationshipWith} onBlind={openBlind} setTab={setTab} accepted={accepted} missions={missions} completions={completions} />}
        {tab==='discover' && <Discover people={filteredPeople} allCount={people.length} relationshipWith={relationshipWith} search={search} setSearch={setSearch} branchFilter={branchFilter} setBranchFilter={setBranchFilter} courseFilter={courseFilter} setCourseFilter={setCourseFilter} ageFilter={ageFilter} setAgeFilter={setAgeFilter} energyFilter={energyFilter} setEnergyFilter={setEnergyFilter} filters={filters} onlineIds={onlineIds} crushIds={crushIds} requestPartner={requestPartner} secretCrush={secretCrush} chemistry={chemistry} openBlind={openBlind} onReport={setReportTarget} />}
        {tab==='requests' && <Requests incoming={incoming} respond={respond} />}
        {tab==='blind' && <BlindMatch people={people} onlineIds={onlineIds} openBlind={openBlind} />}
        {tab==='questions' && <BlindQuestionStudio questions={myBlindQuestions} draft={questionDraft} setDraft={setQuestionDraft} save={saveBlindQuestion} remove={deleteBlindQuestion} />}
        {tab==='chats' && <Chats accepted={accepted} session={session} activeMatch={activeMatch} setActiveMatch={setActiveMatch} currentOther={currentOther} messages={messages} draft={draft} setDraft={setDraft} sendMessage={sendMessage} onlineIds={onlineIds} unread={unreadByConversation} setUnmatchConfirm={setUnmatchConfirm} />}
        {tab==='missions' && <Missions missions={missions} completions={completions} progress={progress} openProof={(m:Mission)=>{setMissionTarget(m);setMissionProof('')}} />}
        {tab==='journey' && <PromJourney progress={progress} completions={completions} xpHistory={xpHistory} badges={badges} tab={activeTabForJourney} setTab={setActiveTabForJourney} />}
        {tab==='memories' && <MemoryVault memories={memories} saveMemory={saveMemory} memoryTitle={memoryTitle} setMemoryTitle={setMemoryTitle} memoryBody={memoryBody} setMemoryBody={setMemoryBody} />}
        {tab==='notifications' && <Notifications items={notifications} markAll={markAllNotifications} />}
        {tab==='profile' && <ProfilePanel profile={profile} form={form} setForm={setForm} save={saveProfile} upload={uploadPhoto} photoFile={photoFile} setPhotoFile={setPhotoFile} loading={loading} config={config} progress={progress} deleteAccount={deleteAccount} />}
        {tab==='admin' && isAdmin && <AdminPanel people={people} reports={reports} search={adminSearch} setSearch={setAdminSearch} moderateReport={moderateReport} toggleBan={toggleBan} />}
      </main>

      {secretCrushIntroOpen && <div className="secret-intro-overlay"><div className="secret-intro-card"><button className="secret-intro-close" onClick={()=>setSecretCrushIntroOpen(false)}>×</button><span className="eyebrow">A LITTLE SECRET 🤫</span><h2>Meet Secret Crush.</h2><p>Choose someone you secretly like. They will never know it was you unless they secretly choose you too. If the feeling is mutual, Prom Pulse reveals the connection to both of you. 💗</p><div className="secret-guide"><div className="secret-guide-top"><span>DISCOVER</span><span>Prom Pulse</span></div><div className="secret-guide-card"><div className="secret-guide-avatar">♡</div><div><b>Someone you might like</b><small>Prom Energy · Your vibe</small></div><div className="secret-guide-heart">♥</div></div><div className="secret-guide-caption">Tap the <b>♡ heart</b> on any profile to send a Secret Crush.</div></div><TooltipHint text="Secret Crush lets you quietly signal interest and only reveals the match if they choose you too."><button className="cta" onClick={()=>{setSecretCrushIntroOpen(false);setTab('discover')}}>Got it · Find a Secret Crush 💗</button></TooltipHint></div></div>}
      {secretMatchPopup && <div className="secret-match-overlay"><div className="secret-match-card"><div className="secret-hearts"><span>💗</span><span>💗</span><span>💗</span></div><span className="eyebrow">IT’S MUTUAL</span><h2>You both have a Secret Crush.</h2><p>{secretMatchPopup.name ? `${secretMatchPopup.name} secretly chose you too.` : 'Your Secret Crush was mutual.'}</p><div className="heart-burst">💘</div><button className="cta" onClick={()=>setSecretMatchPopup(null)}>Keep this secret ✨</button></div></div>}
      {toast && <div className="toast">{toast}</div>}
      {unmatchConfirm && <Modal title="Unmatch?" close={()=>setUnmatchConfirm(null)}><div className="modal-form unmatch-modal"><div className="unmatch-heart">💗</div><h3>Leave this Prom match?</h3><p className="muted">You can discover each other again later. Your profiles will become visible in discovery again.</p><div className="modal-actions"><button className="ghost-button" onClick={()=>setUnmatchConfirm(null)}>Keep match</button><button className="danger-btn" onClick={()=>unmatch(unmatchConfirm)} disabled={loading}>{loading?'Unmatching…':'Unmatch'}</button></div></div></Modal>}
      {reportTarget && <Modal title={`Report ${reportTarget.name}`} close={()=>{setReportTarget(null);setBlockWithReport(false)}}><form onSubmit={submitReport} className="modal-form"><select value={reportReason} onChange={e=>setReportReason(e.target.value)} required><option value="">Choose a reason</option><option>Harassment</option><option>Impersonation</option><option>Inappropriate content</option><option>Spam</option><option>Other</option></select><textarea value={reportDetails} onChange={e=>setReportDetails(e.target.value)} placeholder="Tell the admin team what happened…"/><button type="button" className={blockWithReport?'choice active':'choice'} onClick={()=>setBlockWithReport(x=>!x)}>{blockWithReport?'🔒 Blocked after report':'Block this person too'}</button><p className="muted">Blocking prevents them from seeing your profile. You can still see their profile.</p><button className="cta">Send report</button></form></Modal>}
      {missionTarget && <Modal title={`Complete mission · ${missionTarget.title}`} close={()=>setMissionTarget(null)}><form className="modal-form" onSubmit={submitMissionProof}><p className="muted">Tell yourself the story in one line. This stays private in your profile history.</p><textarea value={missionProof} onChange={e=>setMissionProof(e.target.value)} placeholder="What did you do?" required/><button className="cta">Complete mission ✓</button></form></Modal>}
      {missionCompleteInfo && <Modal title="Mission complete 💗" close={()=>setMissionCompleteInfo(null)}><div className="mission-complete-popup"><div className="heart">💗</div><span className="eyebrow">SAVED TO YOUR PROM STORY</span><h3>{missionCompleteInfo.title}</h3><p>{missionCompleteInfo.description}</p><div className="mission-reward">+{missionCompleteInfo.xp} XP</div><button className="cta" onClick={()=>setMissionCompleteInfo(null)}>Nice ✨</button></div></Modal>}
      {blindTarget && <Modal title={showBlindReveal ? 'Blind Match Reveal ✨' : '60-second Blind Match'} close={()=>{setBlindTarget(null);setBlindSorryPopup(false)}}><div className="blind-modal">{!showBlindReveal ? <><div className="blind-top"><span>Photo hidden</span><b>{blindSeconds}s</b></div>{blindFailed ? <div className="blind-failed"><div className="blind-lock">🔒</div><h3>Blind Match locked</h3><p>That round did not line up. Try another person for a fresh 60-second round.</p><button className="cta" onClick={()=>{setBlindTarget(null);setBlindSorryPopup(false)}}>Back to discovery</button></div> : <><p className="muted">No photo. No profile details. Three interest-based questions. Get all three right before the clock hits zero.</p>{blindQuestions.map((q,i)=><div className="blind-question" key={q.id}><strong>{i+1}. {q.prompt}</strong><div className="blind-options">{q.options.map((opt,j)=><button type="button" key={opt} className={blindAnswers[i]===j?'choice active':'choice'} onClick={()=>setBlindAnswers(a=>a.map((x,k)=>k===i?j:x))}>{opt}</button>)}</div></div>)}<button className="cta" disabled={loading} onClick={submitBlind}>{loading?'Checking…':'Check my answers ✨'}</button></>}</> : <><div className="blind-reveal"><Heart3D compact/><Avatar p={blindTarget} size="xxl"/><h3>{blindTarget.name} · {blindTarget.age || '—'}</h3><p>{blindTarget.course || 'Student'} · {blindTarget.branch || 'Campus'}</p><div className="tags">{(blindTarget.interests||[]).slice(0,4).map(x=><span key={x}>{x}</span>)}</div><p className="reveal-note">You cracked all three. The full profile is unlocked. 💗</p></div>{(() => { const rel = relationshipWith(blindTarget.id); const label = rel.status === 'accepted' ? 'Matched ✓' : rel.status === 'pending' ? 'Requested ✓' : rel.status === 'incoming' ? 'Accept 💗' : 'Ask to Prom 💗'; return <button className="cta" disabled={rel.status === 'accepted' || rel.status === 'pending'} onClick={()=>{setBlindTarget(null);requestPartner(blindTarget.id)}}>{label}</button> })()}</>}</div>{blindSorryPopup && <div className="blind-sorry-overlay"><div className="blind-sorry-card"><div className="blind-sorry-heart">💗</div><span className="eyebrow">NOT THIS TIME</span><h2>Sorry, that one didn't click.</h2><p>Every Prom story has a few wrong turns. There is someone else waiting for your kind of answer.</p><button className="cta" onClick={()=>setBlindSorryPopup(false)}>Try another match ✨</button></div></div>}</Modal>}
    </div>
  )
}


function BlindMatch({ people, onlineIds, openBlind }: { people: Profile[]; onlineIds: string[]; openBlind: (p: Profile) => void }) {
  const available = [...people]
    .filter(p => p?.id)
    .filter((p, i, arr) => arr.findIndex(x => x.id === p.id) === i)
    .sort((a, b) => Number(onlineIds.includes(b.id)) - Number(onlineIds.includes(a.id)))

  return <div className="section">
    <div className="section-head"><div><span className="eyebrow">NO PHOTO · YOUR QUESTIONS · 60 SECONDS</span><TooltipHint text="60-sec Match hides the photo and lets you guess three custom answers before the timer ends."><h2>60-sec Match</h2></TooltipHint><p className="muted">Their photo and profile stay hidden while you guess three answers they wrote themselves.</p></div><span className="count">{available.length} available</span></div>
    {available.length===0 ? <div className="empty panel"><div className="heart">⏱️</div><h3>No one is available yet.</h3><p>Come back when more people join the campus.</p></div> : <div className="discover-grid">
      {available.map(p => <article className="person-card blind-card" key={p.id}>
        <div className="blind-avatar"><span>?</span></div>
        <div className="online-line">{onlineIds.includes(p.id) ? <><i className="live-dot"/> Online now</> : 'Available for a blind round'}</div>
        <span className="eyebrow">PROM MYSTERY</span>
        <h3>Someone from your campus</h3>
        <p className="muted">Three custom questions · 60 seconds</p>
        <div className="tags"><span>♡ No photo</span><span>🎯 Custom answers</span></div>
        <TooltipHint text="60-sec Match is a quick blind round where you answer three questions about their vibe before time runs out."><button className="match-btn" onClick={() => openBlind(p)}>Start 60-sec Match ⏱️</button></TooltipHint>
      </article>)}
    </div>}
  </div>
}

function BlindQuestionStudio({ questions, draft, setDraft, save, remove }: any) {
  return <div className="section"><div className="section-head"><div><span className="eyebrow">MAKE YOURSELF GUESSABLE</span><h2>My 60-sec Questions</h2><p className="muted">Write questions others will answer about you. Keep at least three active questions.</p></div><span className="count">{questions.length} active</span></div>
    <section className="panel page-panel">
      <div className="section-head"><div><span className="eyebrow">QUESTION EDITOR</span><h3>{draft.id ? 'Edit question' : 'Add a new question'}</h3></div><button className="ghost-button" type="button" onClick={()=>setDraft({prompt:'',options:['','','',''],correctIndex:0})}>Clear</button></div>
      <div className="modal-form"><label>Question<input value={draft.prompt} onChange={(e:any)=>setDraft({...draft,prompt:e.target.value})} placeholder="What song would you play on the final dance?"/></label>
      <div className="choice-grid">{draft.options.map((x:string,i:number)=><label key={i}>Option {i+1}<input value={x} onChange={(e:any)=>{const next=[...draft.options];next[i]=e.target.value;setDraft({...draft,options:next})}} /></label>)}</div>
      <div className="onboarding-block"><span className="hint-title">Correct answer</span><div className="choice-grid">{draft.options.map((x:string,i:number)=><button type="button" key={i} className={draft.correctIndex===i?'choice active':'choice'} onClick={()=>setDraft({...draft,correctIndex:i})}>{x || `Option ${i+1}`}</button>)}</div></div>
      <button className="cta" type="button" onClick={save}>{draft.id?'Save question':'Add question'} ✨</button></div>
    </section>
    <div className="mission-grid">{questions.map((q:OwnedBlindQuestion,i:number)=><article className="mission-card-big" key={q.id}><div className="mission-icon">🎯</div><span className="level-chip">QUESTION {i+1}</span><h3>{q.prompt}</h3><p>{q.options.map(o=>o.label).join(' · ')}</p><div className="admin-actions"><button className="ghost-button" onClick={()=>setDraft({id:q.id,prompt:q.prompt,options:q.options.map(o=>o.label),correctIndex:Math.max(0,q.options.findIndex(o=>o.correct))})}>Edit</button><button className="danger-btn" onClick={()=>remove(q.id)}>Remove</button></div></article>)}</div>
  </div>
}

function AuthScreen({ mode, setMode, auth, setAuth, form, setForm, submit, resendOtp, resendBusy, resendCooldown, resendStatus, loading, config, authStep, setAuthStep }: any) {
  const verification = mode === 'signup' && authStep === 'otp'
  return <div className="auth-shell"><div className="auth-visual"><div className="auth-glow"/><Heart3D/><div className="auth-copy"><span className="eyebrow">{config.prom_title}</span><h1>Your college. Your people. Your night.</h1><p>Prom Pulse is the temporary social universe built for the one night you will talk about long after the last song.</p><div className="stat-strip"><span><b>College-only</b> <small>personal email welcome</small></span><span><b>Email OTP</b> <small>one-time signup verification</small></span><span><b>Secret Crush</b> <small>mutual reveals</small></span></div></div></div><div className="auth-card"><div className="brand"><span className="brand-mark">♡</span><span>Prom <b>Pulse</b></span></div><div className="auth-tabs"><button type="button" className={mode==='signup'?'active':''} onClick={()=>{setMode('signup');setAuthStep('email');setAuth({...auth,otp:''})}}>Sign up</button><button type="button" className={mode==='login'?'active':''} onClick={()=>{setMode('login');setAuthStep('email');setAuth({...auth,otp:''})}}>Log in</button></div>{verification ? <form onSubmit={submit}><div className="verification-card"><span className="eyebrow">ONE-TIME VERIFICATION</span><h2>Enter your verification code</h2><p className="muted">We sent an 8-digit one-time code to <b>{auth.email}</b>. You will use your password for future logins.</p><label>OTP code<input inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{8}" minLength={8} maxLength={8} value={auth.otp} onChange={e=>setAuth({...auth,otp:e.target.value.replace(/\D/g,'').slice(0,8)})} placeholder="12345678" required /></label><button className="cta" disabled={loading || auth.otp.length !== 8}>{loading?'Verifying…':'Verify email →'}</button><div className="auth-secondary-actions"><button type="button" className="ghost-button" onClick={resendOtp} disabled={resendBusy || resendCooldown > 0}>{resendBusy ? 'Sending…' : resendCooldown > 0 ? `Resend in ${resendCooldown}s` : 'Resend code'}</button><button type="button" className="ghost-button" onClick={()=>setAuthStep('email')}>Change email</button></div></div></form> : <form onSubmit={submit}><label>Email<input type="email" autoComplete={mode==='login'?'username':'email'} value={auth.email} onChange={e=>setAuth({...auth,email:e.target.value})} placeholder="you@example.com" required /></label><label>Password<input type="password" autoComplete={mode==='login'?'current-password':'new-password'} minLength={8} value={auth.password} onChange={e=>setAuth({...auth,password:e.target.value})} placeholder="At least 8 characters" required /></label>{mode==='signup' ? <p className="muted auth-otp-note">You'll receive a one-time 8-digit verification code once, then use this password for future logins. No phone number or college email required.</p> : <p className="muted auth-otp-note">Use the password you created when you signed up. Email OTP is only used once during signup.</p>}{mode==='signup' && <><label>Full name<input value={form.name} onChange={e=>setForm({...form,name:e.target.value})} required /></label><div className="row"><label>Age<input type="number" min="16" max="100" value={form.age} onChange={e=>setForm({...form,age:e.target.value})} required /></label><label>Year<select value={form.year} onChange={e=>setForm({...form,year:e.target.value})}><option>1st year</option><option>2nd year</option><option>3rd year</option><option>4th year</option><option>PG</option></select></label></div><label>Gender<select value={form.gender} onChange={e=>setForm({...form,gender:e.target.value as Gender | ''})} required><option value="">Select gender</option>{GENDERS.map(x=><option key={x} value={x}>{x[0].toUpperCase()+x.slice(1)}</option>)}</select><small>Used only to personalize who appears in your discovery.</small></label><label>Course<select value={form.course} onChange={e=>setForm({...form,course:e.target.value})} required><option value="">Select course</option>{COURSES.map(x=><option key={x}>{x}</option>)}</select></label><label>Branch<select value={form.branch} onChange={e=>setForm({...form,branch:e.target.value})} required><option value="">Select branch</option>{BRANCHES.map(x=><option key={x}>{x}</option>)}</select></label><div className="onboarding-block"><span className="hint-title">Your Prom Energy</span><div className="choice-grid">{ENERGY.map(x=><button type="button" key={x} title={ENERGY_DESCRIPTIONS[x]} aria-label={`${x}: ${ENERGY_DESCRIPTIONS[x]}`} className={form.prom_energy===x?'choice active':'choice'} onClick={()=>setForm({...form,prom_energy:x})}>{x}</button>)}</div></div><div className="onboarding-block"><span className="hint-title">Ideal Prom Night</span><div className="choice-grid">{PROM_STYLES.map(x=><button type="button" key={x} className={form.prom_style===x?'choice active':'choice'} onClick={()=>setForm({...form,prom_style:x})}>{x}</button>)}</div></div><label>3 things you like <small>comma separated</small><input disabled={form.interests_private} value={form.interests} onChange={e=>setForm({...form,interests:e.target.value})} placeholder={form.interests_private?'Interests hidden':'music, cricket, movies'} /></label><button type="button" className={form.interests_private?'choice active':'choice'} onClick={()=>setForm({...form,interests_private:!form.interests_private})}>{form.interests_private?'🤫 Interests hidden':'I don’t want to reveal my interests'}</button></> }<button className="cta" disabled={loading}>{loading?(mode==='signup'?'Sending…':'Logging in…'):mode==='signup'?'Create account & verify email →':'Log in →'}</button></form>}<p className="auth-note">By joining, you agree to be respectful, protect private conversations, and follow your college's event rules.</p></div></div>
}

function HomeDashboard({ profile, progress, config, countdown, people, picks, chemistry, onlineIds, crushIds, onDiscover, onCrush, onRequest, relationshipWith, onBlind, setTab, accepted, missions, completions }: any) {
  const completed = completions.length
  return <div className="dashboard"><section className="hero-panel panel"><div className="hero-copy"><span className="eyebrow">{countdown.live?'PROM NIGHT MODE':'YOUR PROM UNIVERSE'}</span><h2>{countdown.live?'The night is live. Make a memory.':'Who will be your Prom +1?'}</h2><p>{countdown.live?'Use Live Mode to find your people, talk, and save the night to your Memory Vault.':'Prom Pulse is where college prom stops being a calendar event and becomes a story you can actually take part in.'}</p><div className="hero-actions"><button className="cta" onClick={onDiscover}>Discover people</button><button className="ghost-button" onClick={()=>setTab('missions')}>Play a mission 🎯</button></div></div></section><section className="countdown-panel panel"><div><span className="eyebrow">{config.prom_title}</span><h3>The Night of Unforgettable Stories ✨</h3></div>{countdown.live?<div className="live-mode"><span className="pulse-orb"/> LIVE <b>{people.filter((p:any)=>onlineIds.includes(p.id)).length + 1}</b> people online</div>:<div className="timer"><div><b>{pad(countdown.days)}</b><small>days</small></div><div><b>{pad(countdown.hours)}</b><small>hours</small></div><div><b>{pad(countdown.mins)}</b><small>mins</small></div><div><b>{pad(countdown.secs)}</b><small>secs</small></div></div>}</section><section className="section"><div className="section-head"><div><span className="eyebrow">WHO SHOULD I TALK TO?</span><h3>Tonight's 3 Prom Picks</h3></div><button className="ghost-button" onClick={onDiscover}>See everyone</button></div><div className="pick-grid">{picks.map((p:Profile)=><article className="pick-card" key={p.id}><div className="pick-score">{chemistry(p)}% chemistry</div><Avatar p={p} size="lg"/><div><h3>{p.name} <span>{p.age || ''}</span></h3><p>{p.course || 'Student'} · {p.branch || 'Campus'}</p><div className="tags">{(p.interests || []).slice(0,2).map(x=><span key={x}>{x}</span>)}</div></div><div className="pick-actions"><button className="ghost-icon" onClick={()=>onBlind(p)} title="Blind match">🎯</button><button className="ghost-icon" onClick={()=>onCrush(p)} title="Secret crush">{crushIds.includes(p.id)?'♥':'♡'}</button>{(() => { const rel = relationshipWith(p.id); const label = rel.status === 'accepted' ? 'Matched ✓' : rel.status === 'pending' ? 'Requested ✓' : rel.status === 'incoming' ? 'Accept 💗' : rel.status === 'declined' ? 'Declined' : 'Ask to Prom'; return <button className="match-btn" disabled={rel.status === 'accepted' || rel.status === 'pending' || rel.status === 'declined'} onClick={()=>onRequest(p.id)}>{label}</button> })()}</div></article>)}{picks.length===0&&<div className="empty"><div className="heart">♡</div><p>Your picks will appear as students join.</p></div>}</div></section><section className="mini-grid"><div className="panel chemistry-card"><span className="eyebrow">YOUR PROM CHEMISTRY</span><div className="chemistry-meter"><div style={{width:`${Math.min(70+accepted.length*5,96)}%`}}/></div><div className="chemistry-number">{Math.min(70+accepted.length*5,96)}%</div><p>Keep discovering to sharpen your chemistry circle.</p></div><div className="panel mission-card"><span className="eyebrow">YOUR PROM JOURNEY</span><h3>Level {progress?.level || 1} · {progress?.title || 'Newcomer 💫'}</h3><div className="xp-track"><div style={{width:`${progress ? Math.min(100, Math.max(0, ((progress.xp-(LEVELS.find(l=>l.level===progress.level)?.min||0))/Math.max(1,(nextLevelForXp(progress.xp)?.min||progress.xp+1)-(LEVELS.find(l=>l.level===progress.level)?.min||0)))*100)) : 0}%`}}/></div><p>{progress?.xp || 0} XP · {completed}/{missions.length} missions completed</p><button className="ghost-button" onClick={()=>setTab('journey')}>Open my journey →</button></div><div className="panel live-stats"><span className="eyebrow">CAMPUS PULSE</span><div><b>{people.length}</b><span>students joined</span></div><div><b>{accepted.length}</b><span>your connections</span></div><div><b>{people.filter((p:Profile)=>onlineIds.includes(p.id)).length}</b><span>online now</span></div></div></section></div>
}

function Discover({ people, allCount, relationshipWith, search, setSearch, branchFilter, setBranchFilter, courseFilter, setCourseFilter, ageFilter, setAgeFilter, energyFilter, setEnergyFilter, filters, onlineIds, crushIds, requestPartner, secretCrush, chemistry, openBlind, onReport }: any) {
  return <div className="section"><div className="section-head"><div><span className="eyebrow">CAMPUS-ONLY DISCOVERY</span><h2>Meet people from {allCount ? 'your college' : 'your campus'}.</h2></div><span className="count">{people.length} shown</span></div><div className="filter-bar"><div className="searchbox"><span>⌕</span><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search names, branches, interests…"/></div><select value={branchFilter} onChange={e=>setBranchFilter(e.target.value)}><option value="all">All branches</option>{filters.branches.map((x:string)=><option key={x}>{x}</option>)}</select><select value={courseFilter} onChange={e=>setCourseFilter(e.target.value)}><option value="all">All courses</option>{filters.courses.map((x:string)=><option key={x}>{x}</option>)}</select><select value={ageFilter} onChange={e=>setAgeFilter(e.target.value)}><option value="all">All ages</option><option value="18-19">18–19</option><option value="20-21">20–21</option><option value="22+">22+</option></select><select value={energyFilter} onChange={e=>setEnergyFilter(e.target.value)}><option value="all">All energy</option>{ENERGY.map(x=><option key={x}>{x}</option>)}</select></div><div className="person-grid">{people.map((p:Profile)=><article className="person-card" key={p.id}><div className="card-ribbon">{chemistry(p)}% chemistry</div><button className="more-btn" onClick={()=>onReport(p)}>⋯</button><div className="photo-wrap"><Avatar p={p} size="xl"/><span className={onlineIds.includes(p.id)?'status-badge online':'status-badge'}>{onlineIds.includes(p.id)?'● Online':'○ Around campus'}</span></div><h3>{p.name} <span>{p.age || ''}</span></h3><p className="meta">{p.course || 'Student'} · {p.branch || 'Campus'} · {p.year || ''}</p><div className="tags">{[p.prom_energy, p.prom_style, ...(p.interests || [])].filter(Boolean).slice(0,4).map(x=><span key={x}>{x}</span>)}</div><p className="bio">{p.bio || `Looking for ${p.looking_for || 'a memorable prom night'}.`}</p><div className="card-actions"><button className="ghost-icon" onClick={()=>openBlind(p)} title="Blind match">🎯</button><TooltipHint text="Send a secret crush. They won't know unless they feel the same."><button className="ghost-icon" onClick={()=>secretCrush(p)} title="Secret crush">{crushIds.includes(p.id)?'♥':'♡'}</button></TooltipHint>{(() => { const rel = relationshipWith(p.id); const label = rel.status === 'accepted' ? 'Matched ✓' : rel.status === 'pending' ? 'Requested ✓' : rel.status === 'incoming' ? 'Accept 💗' : rel.status === 'declined' ? 'Declined' : 'Ask to Prom'; return <button className="match-btn" disabled={rel.status === 'accepted' || rel.status === 'pending' || rel.status === 'declined'} onClick={()=>requestPartner(p.id)}>{label}</button> })()}</div></article>)}{people.length===0&&<div className="panel empty"><div className="heart">♡</div><h3>The campus is quiet right now.</h3><p>Try another search, or make sure the other account has completed email verification.</p></div>}</div></div>
}

function Requests({ incoming, respond }: any) {
  const pending = incoming.filter((x:Match)=>x.status==='pending')
  return <div className="panel page-panel"><div className="section-head"><div><span className="eyebrow">YOUR INVITES</span><h2>Requests</h2></div><span className="count">{pending.length} waiting</span></div>{pending.length===0?<div className="empty"><div className="heart">♡</div><h3>No waiting requests</h3><p>Someone may be choosing the right words.</p></div>:pending.map((m:Match)=><div className="request-row" key={m.id}><Avatar p={m.requester} size="md"/><div><strong>{m.requester.name}</strong><span>{m.requester.course || 'Student'} · {m.requester.branch || 'Campus'}</span><small>{m.requester.prom_energy || 'Prom explorer'}</small></div><div className="request-actions"><button className="ghost-button" onClick={()=>respond(m.id,'declined')}>Not this time</button><button className="match-btn" onClick={()=>respond(m.id,'accepted')}>Accept 💗</button></div></div>)}</div>
}

function Chats({ accepted, session, activeMatch, setActiveMatch, currentOther, messages, draft, setDraft, sendMessage, onlineIds, unread, setUnmatchConfirm }: any) {
  return <div className="panel chat-panel"><div className="chat-list"><div className="section-head"><div><span className="eyebrow">REAL-TIME</span><h2>Chats</h2></div><span className="count">{accepted.length}</span></div>{accepted.map((m:Match)=><button className={`chat-pick ${activeMatch?.id===m.id?'selected':''}`} key={m.id} onClick={()=>setActiveMatch(m)}><Avatar p={currentOther(m)} size="sm"/><div><strong>{currentOther(m).name}</strong><span>{onlineIds.includes(currentOther(m).id)?'Online now':'Prom match'}</span></div>{unread[m.id]>0?<span className="unread-badge">{unread[m.id]}</span>:<span>›</span>}</button>)}{accepted.length===0&&<div className="muted">A mutual match unlocks your private conversation.</div>}</div><div className="chat-window">{activeMatch?<><div className="chat-head"><Avatar p={currentOther(activeMatch)} size="sm"/><div><strong>{currentOther(activeMatch).name}</strong><span>{onlineIds.includes(currentOther(activeMatch).id)?'Online now':'Your Prom match'}</span></div><button type="button" className="danger-btn chat-unmatch" onClick={()=>setUnmatchConfirm(activeMatch)}>Unmatch</button></div><div className="messages">{messages.map((m:Message)=><div key={m.id} className={`bubble ${m.sender_id===session.user.id?'mine':''}`}>{m.body}<small>{new Date(m.created_at).toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'})}</small></div>)}{messages.length===0&&<div className="empty-chat"><div className="heart">💗</div><p>Start with something better than “hey”.</p></div>}</div><form className="message-form" onSubmit={sendMessage}><input value={draft} onChange={e=>setDraft(e.target.value)} placeholder="Tell them what would make your Prom night memorable…"/><button>➤</button></form></>:<div className="empty-chat"><Heart3D compact/><h3>Choose a conversation</h3><p>Your private conversations live here.</p></div>}</div></div>
}

function Missions({ missions, completions, progress, openProof }: any) {
  const today = new Date().toISOString().slice(0,10)
  const level = progress?.level || 1
  const active = missions.filter((m:Mission)=> (m.min_level || 1) <= level)
  const future = missions.filter((m:Mission)=> (m.min_level || 1) > level)
  const doneCount = active.filter((m:Mission)=> completions.some((x:Completion)=>x.mission_id===m.id && (!m.is_daily || !x.completion_date || x.completion_date===today))).length
  const currentTier = missions.filter((m:Mission)=>(m.min_level || 1) === level)
  const previousTiers = missions.filter((m:Mission)=>(m.min_level || 1) < level)
  const grouped = future.reduce((acc:any[], m:Mission)=>{ const n=m.min_level || 1; (acc[n] ||= []).push(m); return acc }, [])
  const renderMission = (m: Mission) => { const done = m.is_daily ? completions.some((x:Completion)=>(x.mission_id===m.id && (!x.completion_date || x.completion_date===today))) : completions.some((x: Completion)=>x.mission_id===m.id); return <article className={`mission-card-big ${done?'done':''}`} key={m.id}><div className="mission-icon">{m.icon}</div><span className="xp">+{m.reward_xp} XP</span>{m.is_daily&&<span className="daily-chip">TODAY</span>}<span className="level-chip">LEVEL {m.min_level || 1}</span><h3>{m.title}</h3><p>{m.description}</p><div className="mission-status">{done?(m.is_daily?'Completed today ✓':'Completed ✓'):(m.is_daily?'Daily mission':'Available now')}</div><button className={done?'ghost-button':'match-btn'} disabled={done} onClick={()=>openProof(m)}>{done?'Completed':'Complete mission'}</button></article> }
  return <div className="section"><div className="section-head"><div><span className="eyebrow">PLAY, MEET, REMEMBER</span><TooltipHint text="Missions are quick ways to earn XP, level up, and unlock new Prom Pulse perks."><h2>Prom Missions</h2></TooltipHint><p className="muted">Level {level} is unlocked. Your newest challenges are below.</p></div><span className="count">{doneCount}/{active.length} active missions completed</span></div>
    {currentTier.length>0 ? <><div className="section-head"><div><span className="eyebrow">NEWLY UNLOCKED</span><h3>Level {level} Missions 🔓</h3></div></div><div className="mission-grid">{currentTier.map(renderMission)}</div></> : <div className="panel empty"><div className="heart">🎯</div><h3>No missions were loaded for Level {level}.</h3><p>Refresh the page after the mission catalog syncs.</p></div>}
    {previousTiers.length>0 && <><div className="section-head"><div><span className="eyebrow">MISSION HISTORY</span><h3>Earlier Levels</h3></div></div><div className="mission-grid">{previousTiers.map(renderMission)}</div></>}
    <div className="locked-missions"><div className="section-head"><div><span className="eyebrow">COMING NEXT</span><h3>Future Mission Tiers</h3></div></div><div className="mission-grid">{Object.keys(grouped).sort((a,b)=>Number(a)-Number(b)).slice(0,4).map(k=><article className="mission-card-big locked" key={k}><div className="mission-icon">🔒</div><span className="level-chip">LEVEL {k}</span><h3>Unlock at Level {k}</h3><p>{grouped[Number(k)][0]?.description || 'New challenges are waiting for you.'}</p><div className="mission-status">{Number(k)-level} level{Number(k)-level===1?'':'s'} away</div></article>)}</div></div></div>
}

function PromJourney({ progress, completions, xpHistory, badges, tab, setTab }: any) {
  const xp = progress?.xp || 0
  const level = progress?.level || 1
  const current = LEVELS.find(x => x.level === level) || LEVELS[0]
  const next = nextLevelForXp(xp)
  const pct = next ? Math.min(100, Math.round(((xp-current.min)/(next.min-current.min))*100)) : 100
  return <div className="section journey-page"><div className="journey-hero panel"><div><span className="eyebrow">YOUR PROM JOURNEY</span><h2>Level {level} · {progress?.title || current.title}</h2><p>{next ? `${next.min-xp} XP to Level ${next.level}.` : 'You reached the top tier. Prom Legend forever.'}</p><div className="xp-track large"><div style={{width:`${pct}%`}}/></div><div className="xp-numbers"><b>{xp} XP</b><span>{next ? `${next.min-xp} to next unlock` : 'MAX LEVEL'}</span></div></div><div className="journey-heart"><Heart3D compact/></div></div><div className="journey-tabs">{(['progress','badges','history'] as const).map(x=><button key={x} onClick={()=>setTab(x)} className={tab===x?'active':''}>{x==='progress'?'Unlocks':x==='badges'?'Badges':'XP history'}</button>)}</div>{tab==='progress'&&<div className="unlock-grid">{LEVELS.map(l=><article key={l.level} className={`unlock-card ${xp>=l.min?'unlocked':''}`}><span>Level {l.level}</span><h3>{l.title}</h3><p>{l.unlock}</p>{xp>=l.min?<b>Unlocked ✓</b>:<small>{l.min-xp} XP needed</small>}</article>)}</div>}{tab==='badges'&&<div className="badge-grid">{badges.length?badges.map((b:Badge)=><article className="badge-card" key={b.id}><div>{b.icon}</div><h3>{b.name}</h3><p>{b.description}</p><span>Earned</span></article>):<div className="empty"><div className="heart">🏅</div><p>Your first badge is waiting for you.</p></div>}</div>}{tab==='history'&&<div className="history-list">{xpHistory.length?xpHistory.map((x:XPTransaction)=><div className="history-row" key={x.id}><span>{new Date(x.created_at).toLocaleDateString()}</span><strong>+{x.amount} XP</strong><small>{x.source.replaceAll('_',' ')}</small></div>):<div className="empty"><p>Complete a mission to start your XP history.</p></div>}</div>}</div>
}

function MemoryVault({ memories, saveMemory, memoryTitle, setMemoryTitle, memoryBody, setMemoryBody }: any) {
  return <div className="memory-layout"><section className="panel page-panel"><span className="eyebrow">YOUR PROM STORY</span><h2>Memory Vault</h2><p className="muted">A private place for the little details you never want the night to lose.</p><form className="memory-form" onSubmit={saveMemory}><input value={memoryTitle} onChange={e=>setMemoryTitle(e.target.value)} placeholder="Memory title" required/><textarea value={memoryBody} onChange={e=>setMemoryBody(e.target.value)} placeholder="What happened? Why do you want to remember it?"/><button className="cta">Save memory 💗</button></form></section><section className="memory-stack">{memories.length===0?<div className="panel empty"><Heart3D compact/><h3>Your vault is empty.</h3><p>Save your first memory before the night even begins.</p></div>:memories.map((m:Memory)=><article className="memory-card" key={m.id}><div className="memory-pin">✦</div><span>{m.event_kind === 'prom-night' ? 'PROM NIGHT' : 'BEFORE PROM'}</span><h3>{m.title}</h3><p>{m.body}</p><small>{new Date(m.created_at).toLocaleDateString()}</small></article>)}</section></div>
}

function Notifications({ items, markAll }: any) {
  return <div className="panel page-panel"><div className="section-head"><div><span className="eyebrow">THE LITTLE THINGS</span><h2>Notifications</h2></div><button className="ghost-button" onClick={markAll}>Mark all read</button></div>{items.length===0?<div className="empty"><div className="heart">♡</div><h3>Nothing yet.</h3></div>:items.map((n:Notification)=><div className={`notification-row ${n.read_at?'':'unread'}`} key={n.id}><div className="notif-icon">{n.type.includes('crush')?'♥':n.type==='message'?'◌':n.type==='match'?'💗':'♡'}</div><div><strong>{n.title}</strong><p>{n.body}</p><small>{new Date(n.created_at).toLocaleString()}</small></div></div>)}</div>
}

function ProfilePanel({ profile, form, setForm, save, upload, photoFile, setPhotoFile, loading, config, progress, deleteAccount }: any) {
  return <div className="profile-layout"><section className="panel profile-preview"><div className="profile-photo-large"><Avatar p={profile} size="xxl"/></div><h2>{profile?.name}</h2><p>{config.college_name}</p><div className="profile-level"><span>Level {progress?.level || 1}</span><b>{progress?.title || 'Newcomer 💫'}</b><small>{progress?.xp || 0} XP</small></div>{!profile?.gender && <div className="gender-required">Choose your gender below to unlock gender-matched discovery.</div>}<div className="profile-badges"><span>{profile?.prom_energy}</span><span>{profile?.prom_style}</span><span>{profile?.looking_for}</span></div><div className="profile-heart"><Heart3D compact/></div><div className="profile-danger-zone"><span className="eyebrow">ACCOUNT</span><p className="muted">Permanently remove your Prom Pulse account and its associated data.</p><button type="button" className="danger-btn" onClick={deleteAccount} disabled={loading}>Delete account permanently</button></div></section><form className="panel profile-form" onSubmit={save}><span className="eyebrow">YOUR PROM IDENTITY</span><h2>Make it feel like you.</h2><div className="photo-upload"><input type="file" accept="image/*" onChange={e=>setPhotoFile(e.target.files?.[0] || null)}/><button type="button" className="ghost-button" onClick={upload} disabled={!photoFile || loading}>Upload photo</button></div><label>Full name<input value={form.name} onChange={e=>setForm({...form,name:e.target.value})} required/></label><div className="row"><label>Age<input type="number" min="16" max="100" value={form.age} onChange={e=>setForm({...form,age:e.target.value})}/></label><label>Year<select value={form.year} onChange={e=>setForm({...form,year:e.target.value})}><option>1st year</option><option>2nd year</option><option>3rd year</option><option>4th year</option><option>PG</option></select></label></div><label>Gender<select value={form.gender} onChange={e=>setForm({...form,gender:e.target.value as Gender | ''})} required><option value="">Select gender</option>{GENDERS.map(x=><option key={x} value={x}>{x[0].toUpperCase()+x.slice(1)}</option>)}</select><small>Used only to personalize who appears in your discovery.</small></label><label>Course<select value={form.course} onChange={e=>setForm({...form,course:e.target.value})}><option value="">Select course</option>{COURSES.map(x=><option key={x}>{x}</option>)}</select></label><label>Branch<select value={form.branch} onChange={e=>setForm({...form,branch:e.target.value})}><option value="">Select branch</option>{BRANCHES.map(x=><option key={x}>{x}</option>)}</select></label><label>Interests<small>comma separated</small><input disabled={form.interests_private} value={form.interests} onChange={e=>setForm({...form,interests:e.target.value})} placeholder={form.interests_private?'Interests hidden':'music, cricket, movies'}/></label><button type="button" className={form.interests_private?'choice active':'choice'} onClick={()=>setForm({...form,interests_private:!form.interests_private})}>{form.interests_private?'🤫 Interests hidden':'I don’t want to reveal my interests'}</button><label>Bio<textarea value={form.bio} onChange={e=>setForm({...form,bio:e.target.value})}/></label><div className="onboarding-block"><span className="hint-title">Prom Energy</span><div className="choice-grid">{ENERGY.map(x=><button type="button" title={ENERGY_DESCRIPTIONS[x]} aria-label={`${x}: ${ENERGY_DESCRIPTIONS[x]}`} className={form.prom_energy===x?'choice active':'choice'} key={x} onClick={()=>setForm({...form,prom_energy:x})}>{x}</button>)}</div></div><div className="onboarding-block"><span className="hint-title">Ideal Prom Night</span><div className="choice-grid">{PROM_STYLES.map(x=><button type="button" className={form.prom_style===x?'choice active':'choice'} key={x} onClick={()=>setForm({...form,prom_style:x})}>{x}</button>)}</div></div><button className="cta" disabled={loading}>{loading?'Saving…':'Save profile'}</button></form></div>
}

function AdminPanel({ people, reports, search, setSearch, moderateReport, toggleBan }: any) {
  const filtered = people.filter((p:Profile)=>!search || [p.name,p.email,p.course,p.branch].filter(Boolean).some(v=>String(v).toLowerCase().includes(search.toLowerCase())))
  const open = reports.filter((r:Report)=>['open','reviewing'].includes(r.status))
  return <div className="admin-grid"><div className="stats-row"><div className="stat-card"><span>Total users</span><b>{people.length}</b></div><div className="stat-card"><span>Open reports</span><b>{open.length}</b></div><div className="stat-card"><span>Suspended</span><b>{people.filter((p:Profile)=>p.banned_at).length}</b></div></div><section className="panel page-panel"><div className="section-head"><div><span className="eyebrow">MODERATION</span><h2>Reports</h2></div></div>{open.length===0?<p className="muted">No open reports.</p>:open.map((r:Report)=><div className="admin-row" key={r.id}><div><strong>{r.reported?.name}</strong><span>{r.reason}</span><p>{r.details || 'No details.'}</p></div><div className="admin-actions"><button className="ghost-button" onClick={()=>moderateReport(r.id,'dismissed')}>Dismiss</button><button className="danger-btn" onClick={()=>moderateReport(r.id,'resolved')}>Resolve</button><button className="danger-btn" onClick={()=>toggleBan(r.reported_id,true)}>Suspend</button></div></div>)}</section><section className="panel page-panel"><div className="section-head"><div><span className="eyebrow">USER MANAGEMENT</span><h2>Students</h2></div><div className="searchbox compact"><span>⌕</span><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search students…"/></div></div>{filtered.map((p:Profile)=><div className="admin-row" key={p.id}><div className="admin-user"><Avatar p={p} size="sm"/><div><strong>{p.name}</strong><span>{p.course || 'Student'} · {p.branch || ''}</span></div></div><div className="admin-actions">{p.banned_at?<button className="ghost-button" onClick={()=>toggleBan(p.id,false)}>Restore</button>:<button className="danger-btn" onClick={()=>toggleBan(p.id,true)}>Suspend</button>}</div></div>)}</section></div>
}

function Avatar({ p, size='md' }: { p?: Profile | null; size?: string }) {
  return p?.avatar_url ? <img className={`avatar-img avatar-${size}`} src={p.avatar_url} alt={p.name || 'profile'}/> : <div className={`avatar avatar-${size}`}>{p?.name?.[0]?.toUpperCase() || '?'}</div>
}
function NavButton({ active, onClick, label, count, icon }: any) { return <button className={`nav-btn ${active?'active':''}`} onClick={onClick}><span>{icon}</span>{label}{count ? <b>{count}</b> : null}</button> }
function TooltipHint({ text, children }: { text: string; children: React.ReactNode }) {
  return <span className="tooltip-wrap" tabIndex={0} aria-label={text}><span className="tooltip-trigger">{children}</span><span className="tooltip-bubble" role="tooltip">{text}</span></span>
}
function Modal({ title, close, children }: any) { return <div className="modal-backdrop" onClick={e=>e.currentTarget===e.target&&close()}><div className="modal"><div className="modal-head"><h3>{title}</h3><button onClick={close}>×</button></div>{children}</div></div> }
function pad(n:number) { return String(n).padStart(2,'0') }
function Heart3D({ compact=false }: {compact?: boolean}) { return <div className={`heart-stage ${compact?'compact':''}`} aria-hidden="true"><div className="heart-halo"/><div className="heart-3d"><i/><i/><i/></div><div className="heart-ring ring-a"/><div className="heart-ring ring-b"/><div className="heart-glint"/></div> }
