import 'dart:async';
import 'dart:convert';
import 'dart:ui'; // For ImageFilter
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

// -----------------------------------------------------------------------------
// 0. CONFIGURATION & CONSTANTS
// -----------------------------------------------------------------------------

const kPrimaryColor = Color(0xFFF97316); // Orange-500
const kBackgroundColor = Color(0xFF02040A); // Very Dark Blue
const kPanelColor = Color(0xFF09090B); // Zinc-950
const kCardColor = Color(0xFF18181B); // Zinc-900
const kTextColor = Colors.white;
const kTextMutedColor = Color(0xFF94A3B8); // Slate-400
const kAccentSuccess = Color(0xFF22C55E); // Green-500
const kAccentError = Color(0xFFEF4444); // Red-500

const String kApiEndpoint =
    'https://ll.thespacedevs.com/2.2.0/launch/upcoming/?limit=50';
const String kRocketHeroImage =
    'https://images.unsplash.com/photo-1516849841032-87dbac4dcb68?q=80&w=2070&auto=format&fit=crop'; // Dark Trajectory
const String kLandingBgImage =
    'https://images.unsplash.com/photo-1451187580459-43490279c0fa?q=80&w=2072&auto=format&fit=crop'; // Deep Space Network

// -----------------------------------------------------------------------------
// 0.1 NORMALIZATION HELPERS
// -----------------------------------------------------------------------------

String normalizeAgency(String name) {
  final n = name.toLowerCase();
  if (n.contains('china aerospace') || n.contains('casc')) return 'CASC';
  if (n.contains('indian space') || n.contains('isro')) return 'ISRO';
  if (n.contains('space exploration') || n.contains('spacex')) return 'SPACEX';
  if (n.contains('national aeronautics') || n.contains('nasa')) return 'NASA';
  if (n.contains('roscosmos')) return 'ROSCOSMOS';
  if (n.contains('european space')) return 'ESA';
  if (n.contains('blue origin')) return 'BLUE ORIGIN';
  if (n.contains('rocket lab')) return 'ROCKET LAB';
  if (n.contains('united launch alliance') || n.contains('ula')) return 'ULA';
  if (n.length > 20) return name.substring(0, 20).toUpperCase();
  return name.toUpperCase();
}

String normalizeStatusLabel(String status) {
  final s = status.toLowerCase();
  if (s.contains('success')) return 'SUCCESSFUL';
  if (s.contains('go') || s.contains('confirm')) return 'CONFIRMED';
  return 'PENDING';
}

Color getStatusColor(String statusLabel) {
  if (statusLabel == 'SUCCESSFUL') return kAccentSuccess; // Green
  if (statusLabel == 'CONFIRMED') return kPrimaryColor; // Orange
  return Colors.grey; // Pending
}

// -----------------------------------------------------------------------------
// 1. MODELS
// -----------------------------------------------------------------------------

class LaunchSpecs {
  final String height;
  final String mass;
  final String stages;
  final String payload;

  LaunchSpecs({
    this.height = 'N/A',
    this.mass = 'N/A',
    this.stages = 'N/A',
    this.payload = 'N/A',
  });
}

class Launch {
  final String id;
  final String company;
  final String country; // ISO code
  final String rocketType;
  final String rocketName;
  final DateTime? tentativeDate;
  final String site;
  final String status;
  final String image;
  final LaunchSpecs specs;
  final String missionName;

  Launch({
    required this.id,
    required this.company,
    required this.country,
    required this.rocketType,
    required this.rocketName,
    this.tentativeDate,
    required this.site,
    required this.status,
    required this.image,
    required this.specs,
    required this.missionName,
  });

  factory Launch.fromJson(Map<String, dynamic> json) {
    // Parsing logic adapting from specification
    final id = json['id'] ?? '';
    final name = json['name'] ?? 'Unknown Mission';

    // Split name "Rocket | Mission" if possible
    final parts = name.toString().split(' | ');
    final rocketNameRaw = parts.isNotEmpty ? parts[0] : 'Unknown Rocket';
    final missionNameRaw = parts.length > 1 ? parts[1] : name;

    final serviceProvider = json['launch_service_provider'] ?? {};
    final company = normalizeAgency(
      serviceProvider['name'] ?? 'Unknown Company',
    );

    // Status
    final statusObj = json['status'] ?? {};
    final statusName = statusObj['abbrev'] ?? 'TBD';

    // Date
    final netStr = json['net'];
    final DateTime? netDate = netStr != null ? DateTime.tryParse(netStr) : null;

    // Pad/Location
    final pad = json['pad'] ?? {};
    final location = pad['location'] ?? {};
    final site = location['name'] ?? 'Unknown Site';
    final locationCountryCode = location['country_code'] ?? 'UNK';

    // Rocket Config
    final rocket = json['rocket'] ?? {};
    final config = rocket['configuration'] ?? {};
    final image = config['image_url'] ?? '';

    // We try to fetch rudimentary specs if available or mock them as API doesn't always strictly return mass/height in simple list
    // In a real app we might fetch detail. For now, we mock specs or leave N/A
    // Adapting "No backend" constraint means we use what we have.

    return Launch(
      id: id,
      company: company,
      country: locationCountryCode, // Use launch site country
      rocketType: config['family'] ?? rocketNameRaw,
      rocketName: rocketNameRaw,
      tentativeDate: netDate,
      site: site,
      status: statusName,
      image: image,
      specs: LaunchSpecs(), // Placeholder
      missionName: missionNameRaw,
    );
  }

  String get dateDisplay {
    if (tentativeDate == null) return 'TBD';
    return DateFormat('MMM dd, HH:mm').format(tentativeDate!.toLocal());
  }
}

// -----------------------------------------------------------------------------
// 2. MAIN APP
// -----------------------------------------------------------------------------

void main() {
  runApp(const RocketCoreApp());
}

class RocketCoreApp extends StatelessWidget {
  const RocketCoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rocket Core',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBackgroundColor,
        primaryColor: kPrimaryColor,
        textTheme: TextTheme(
          bodyMedium: GoogleFonts.jetBrainsMono(
            color: kTextColor,
            fontSize: 13,
          ),
          bodySmall: GoogleFonts.jetBrainsMono(
            color: kTextMutedColor,
            fontSize: 11,
          ),
          titleLarge: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            fontSize: 24,
            letterSpacing: -1,
          ),
          titleMedium: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        colorScheme: const ColorScheme.dark(
          primary: kPrimaryColor,
          surface: kCardColor,
        ),
      ),
      home: const MainLayout(),
    );
  }
}

// -----------------------------------------------------------------------------
// 3. MAIN LAYOUT & STATE
// -----------------------------------------------------------------------------

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout>
    with SingleTickerProviderStateMixin {
  String _view = 'home'; // 'home' | 'main'

  // Data
  List<Launch> _launches = [];
  bool _loading = false;
  String? _error;
  DateTime? _lastUpdate;

  // Filters
  String? _filterCountry; // 'USA', 'RUS', 'CHN'

  // Header State
  bool _showStickyHeader = false;

  // Timer
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _startTimer();
    _fetchLaunches();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  Future<void> _fetchLaunches() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http.get(Uri.parse(kApiEndpoint));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List;
        setState(() {
          _launches = results.map((e) => Launch.fromJson(e)).toList();
          _lastUpdate = DateTime.now();
          _loading = false;
        });
      } else if (response.statusCode == 429) {
        throw "Global rate limit reached";
      } else {
        throw "Satellite link interrupted (${response.statusCode})";
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _enterMainView() {
    setState(() => _view = 'main');
  }

  List<Launch> get _filteredLaunches {
    if (_filterCountry == null) {
      return _launches;
    }
    return _launches.where((l) {
      if (_filterCountry == 'USA') return l.country == 'USA';
      if (_filterCountry == 'RUS') {
        return l.country == 'RUS' || l.country == 'KAZ';
      }
      if (_filterCountry == 'CHN') return l.country == 'CHN';
      return false;
    }).toList();
  }

  bool _handleScroll(ScrollNotification notification) {
    if (notification.metrics.axis == Axis.vertical) {
      final show = notification.metrics.pixels > 180;
      if (show != _showStickyHeader) {
        setState(() {
          _showStickyHeader = show;
        });
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_view == 'home') {
      return LandingView(onEnter: _enterMainView);
    }
    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: _handleScroll,
        child: Stack(
          children: [
            // Content
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // Hero
                SliverToBoxAdapter(child: HeroSection(launches: _launches)),
                // Data Header & List
                SliverPadding(
                  padding: const EdgeInsets.only(top: 20, bottom: 40),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 1000),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DataPanelHeader(
                              lastUpdate: _lastUpdate,
                              onRefresh: _fetchLaunches,
                              loading: _loading,
                              onFilter: (c) => setState(
                                () => _filterCountry = (_filterCountry == c
                                    ? null
                                    : c),
                              ),
                              activeFilter: _filterCountry,
                            ),
                            const SizedBox(
                              height: 0,
                            ), // Spacing handled inside Layout now
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 20),
                                child: ErrorBanner(
                                  error: _error!,
                                  onDismiss: () =>
                                      setState(() => _error = null),
                                ),
                              ),
                            if (_error == null)
                              ..._filteredLaunches.map(
                                (l) => LaunchCard(launch: l, now: _now),
                              ),

                            if (_filteredLaunches.isEmpty &&
                                _error == null &&
                                !_loading)
                              const Padding(
                                padding: EdgeInsets.all(40.0),
                                child: Text(
                                  "NO SCHEDULED LAUNCHES DETECTED FOR PARAMETERS",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: kTextMutedColor),
                                ),
                              ),

                            if (_loading && _launches.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(40),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: kPrimaryColor,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Sticky Header
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              top: _showStickyHeader ? 0 : -100,
              left: 0,
              right: 0,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    height: 80,
                    color: Colors.black.withValues(alpha: 0.7),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "ROCKET",
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          color: kPrimaryColor,
                          child: Text(
                            "CORE",
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                              fontStyle: FontStyle.italic,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 4. LANDING VIEW
// -----------------------------------------------------------------------------

class LandingView extends StatefulWidget {
  final VoidCallback onEnter;
  const LandingView({super.key, required this.onEnter});

  @override
  State<LandingView> createState() => _LandingViewState();
}

class _LandingViewState extends State<LandingView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _clicked = false;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleStart() {
    if (_clicked) return;
    setState(() => _clicked = true);
    // Rapid jump
    Future.delayed(const Duration(milliseconds: 200), widget.onEnter);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Background Image with Blur/Vignette
          Positioned.fill(
            child: Image.network(kLandingBgImage, fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    kBackgroundColor.withValues(alpha: 0.3),
                    kBackgroundColor.withValues(alpha: 0.8),
                    kBackgroundColor,
                  ],
                  stops: const [0.0, 0.6, 1.0],
                  radius: 1.2,
                ),
              ),
            ),
          ),

          // Sonar Animation
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                size: Size.infinite,
                painter: SonarPainter(_controller.value),
              );
            },
          ),

          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "ROCKET",
                style: GoogleFonts.inter(
                  fontSize: 60,
                  fontWeight: FontWeight.w900,
                  height: 0.9,
                  color: Colors.white,
                ),
              ),
              Container(
                color: kPrimaryColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
                child: Text(
                  "CORE",
                  style: GoogleFonts.inter(
                    fontSize: 60,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    fontStyle: FontStyle.italic,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 80),

              MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hovering = true),
                onExit: (_) => setState(() => _hovering = false),
                child: GestureDetector(
                  onTap: _handleStart,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _clicked ? 0.0 : 1.0,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      width: _clicked ? 150 : 100,
                      height: _clicked ? 150 : 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _clicked
                            ? kPrimaryColor.withValues(alpha: 0.1)
                            : Colors.transparent,
                        border: Border.all(
                          color: _hovering ? Colors.white : kPrimaryColor,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_hovering ? Colors.white : kPrimaryColor)
                                .withValues(alpha: 0.4),
                            blurRadius: _hovering ? 30 : 20,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        "START",
                        style: GoogleFonts.jetBrainsMono(
                          fontWeight: FontWeight.bold,
                          color: _hovering ? Colors.white : kPrimaryColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // print("Painting grid");
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    // Vertical lines
    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // Horizontal lines
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class StarfieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.2);
    final random = math.Random(42); // Fixed seed for stability
    for (int i = 0; i < 150; i++) {
      paint.strokeWidth = random.nextDouble() * 2;
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        random.nextDouble() * 1.5,
        paint,
      );
    }

    // Crosshairs
    paint.color = kPrimaryColor.withValues(alpha: 0.1);
    paint.strokeWidth = 1;
    final w = size.width;
    final h = size.height;

    canvas.drawLine(
      Offset(w * 0.1, h * 0.1),
      Offset(w * 0.1 + 20, h * 0.1),
      paint,
    );
    canvas.drawLine(
      Offset(w * 0.1, h * 0.1),
      Offset(w * 0.1, h * 0.1 + 20),
      paint,
    );

    canvas.drawLine(
      Offset(w * 0.9, h * 0.9),
      Offset(w * 0.9 - 20, h * 0.9),
      paint,
    );
    canvas.drawLine(
      Offset(w * 0.9, h * 0.9),
      Offset(w * 0.9, h * 0.9 - 20),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SonarPainter extends CustomPainter {
  final double value;
  SonarPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = kPrimaryColor.withValues(alpha: 0.1);

    for (int i = 0; i < 3; i++) {
      double r = (value + i * 0.33) % 1.0;
      paint.color = kPrimaryColor.withValues(alpha: (1.0 - r) * 0.2);
      canvas.drawCircle(center, r * size.height * 0.6, paint);
    }
  }

  @override
  bool shouldRepaint(SonarPainter oldDelegate) => true;
}

// -----------------------------------------------------------------------------
// 5. HERO & HEADER COMPONENTS
// -----------------------------------------------------------------------------

class HeroSection extends StatelessWidget {
  final List<Launch> launches;
  const HeroSection({super.key, required this.launches});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.35,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            kRocketHeroImage,
            fit: BoxFit.cover,
            color: Colors.black.withValues(alpha: 0.5),
            colorBlendMode: BlendMode.darken,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.2),
                  Colors.black.withValues(alpha: 0.9),
                  kBackgroundColor,
                ],
                stops: const [0.0, 0.4, 0.8, 1.0],
              ),
            ),
          ),
          // Brutalist Overlay Pattern
          Opacity(
            opacity: 0.1,
            child: CustomPaint(painter: GridPainter(), size: Size.infinite),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "REAL-TIME SPACEFLIGHT",
                  style: GoogleFonts.jetBrainsMono(
                    color: kPrimaryColor,
                    letterSpacing: 4,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "ROCKET",
                      style: GoogleFonts.inter(
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        height: 0.9,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      color: kPrimaryColor,
                      child: Text(
                        "CORE",
                        style: GoogleFonts.inter(
                          fontSize: 72,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          height: 0.9,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "GLOBAL LAUNCH TRACKER",
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    color: Colors.white38,
                    letterSpacing: 6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 6. DATA PANEL COMPONENTS
// -----------------------------------------------------------------------------

class DataPanelHeader extends StatelessWidget {
  final DateTime? lastUpdate;
  final bool loading;
  final VoidCallback onRefresh;
  final Function(String) onFilter;
  final String? activeFilter;

  const DataPanelHeader({
    super.key,
    this.lastUpdate,
    required this.loading,
    required this.onRefresh,
    required this.onFilter,
    this.activeFilter,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Bar: Title + Filter
        Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: kBackgroundColor, // Very dark panel header
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "SCHEDULE",
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 12, color: kTextMutedColor),
                      const SizedBox(width: 6),
                      Text(
                        lastUpdate != null
                            ? "SYNC: ${DateFormat('MM/dd/yyyy, HH:mm:ss a').format(lastUpdate!)}"
                            : "OFFLINE",
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: kTextMutedColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Filter Section
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    Text(
                      "FILTER PROGRAM:",
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white38,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _FilterBtn(
                      flag: "🇺🇸",
                      active: activeFilter == 'USA',
                      onTap: () => onFilter('USA'),
                    ),
                    const SizedBox(width: 4),
                    _FilterBtn(
                      flag: "🇷🇺",
                      active: activeFilter == 'RUS',
                      onTap: () => onFilter('RUS'),
                    ),
                    const SizedBox(width: 4),
                    _FilterBtn(
                      flag: "🇨🇳",
                      active: activeFilter == 'CHN',
                      onTap: () => onFilter('CHN'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Sub-bar: Label + Sync Button
        Container(
          color: kBackgroundColor, // Gap color or same as background
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "GLOBAL PIPELINE (NEXT 20)",
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: kTextMutedColor,
                  letterSpacing: 1.5,
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: kPrimaryColor,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: onRefresh,
                  padding: EdgeInsets.zero,
                  icon: loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.sync, color: Colors.black, size: 16),
                  tooltip: "Sync Feed",
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterBtn extends StatelessWidget {
  final String flag;
  final bool active;
  final VoidCallback onTap;

  const _FilterBtn({
    required this.flag,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.white10 : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          flag,
          style: TextStyle(
            fontSize: 16,
            color: active ? null : Colors.white.withValues(alpha: 0.3),
            // Use greyscale filter if inactive? Simplest is opacity for now or color blend.
            // Emoji flags are hard to grayscale in text mostly. Opacity helps.
          ),
        ),
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  final String error;
  final VoidCallback onDismiss;
  const ErrorBanner({super.key, required this.error, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kAccentError.withValues(alpha: 0.1),
        border: Border.all(color: kAccentError),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: kAccentError),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              error,
              style: GoogleFonts.jetBrainsMono(color: kAccentError),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: kAccentError),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 7. LAUNCH CARD & DETAILS
// -----------------------------------------------------------------------------

class LaunchCard extends StatefulWidget {
  final Launch launch;
  final DateTime now;
  const LaunchCard({super.key, required this.launch, required this.now});

  @override
  State<LaunchCard> createState() => _LaunchCardState();
}

class _LaunchCardState extends State<LaunchCard> {
  bool _hovering = false;

  void _showDetails() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: LaunchDetailsModal(launch: widget.launch),
      ),
    );
  }

  String get _flagEmoji {
    final c = widget.launch.country;
    if (c == 'USA') return '🇺🇸';
    if (c == 'RUS' || c == 'KAZ') return '🇷🇺';
    if (c == 'CHN') return '🇨🇳';
    if (c == 'IND') return '🇮🇳';
    if (c == 'JPN') return '🇯🇵';
    if (c == 'EUR') return '🇪🇺';
    return '🌍';
  }

  Color getStatusColor(String status) {
    switch (status) {
      case 'SUCCESS':
        return const Color(0xFF22C55E); // Green
      case 'CONFIRMED':
      case 'GO':
        return kPrimaryColor; // Orange
      case 'PENDING':
        return Colors.blueAccent; // Blue
      case 'FAILURE':
        return kAccentError; // Red
      default:
        return Colors.white30; // Grey for unknown/other
    }
  }

  String normalizeStatusLabel(String status) {
    final lowerStatus = status.toLowerCase();
    if (lowerStatus.contains('success')) return 'SUCCESS';
    if (lowerStatus.contains('confirmed')) return 'CONFIRMED';
    if (lowerStatus.contains('go')) return 'GO';
    if (lowerStatus.contains('pending')) return 'PENDING';
    if (lowerStatus.contains('failure')) return 'FAILURE';
    if (lowerStatus.contains('tbd')) return 'TBD';
    return status.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final statusLabel = normalizeStatusLabel(widget.launch.status);
    final statusColor = getStatusColor(statusLabel);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _showDetails,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D0F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovering
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.05),
            ),
            boxShadow: _hovering
                ? [
                    BoxShadow(
                      color: kPrimaryColor.withValues(alpha: 0.05),
                      blurRadius: 20,
                      spreadRadius: 0,
                    ),
                  ]
                : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER ROW: Flag + Mission Info + Status
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Flag
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _flagEmoji,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Mission Name & Rocket
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.launch.missionName,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 16, // Readable on mobile
                            color: Colors.white,
                            height: 1.1,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${widget.launch.rocketName} • ${widget.launch.site}"
                              .toUpperCase(),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: Colors.white54,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Status Pill (Compact)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      statusLabel == 'CONFIRMED' ? 'GO' : statusLabel,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.05)),
              const SizedBox(height: 12),

              // SECOND ROW: Date & Search
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 14,
                        color: kPrimaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.launch.dateDisplay,
                        style: GoogleFonts.jetBrainsMono(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: kPrimaryColor, // Highlight date
                        ),
                      ),
                    ],
                  ),

                  // Search Button (Small, convenient)
                  InkWell(
                    onTap: () {
                      launchUrl(
                        Uri.parse(
                          "https://www.google.com/search?q=wikipedia+rocket+${widget.launch.rocketName}+${widget.launch.missionName}",
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                      child: const Icon(
                        Icons.search,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LaunchDetailsModal extends StatelessWidget {
  final Launch launch;
  const LaunchDetailsModal({super.key, required this.launch});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 1000,
        height: 600,
        decoration: BoxDecoration(
          color: kPanelColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            // Left Feature Image
            Expanded(
              flex: 4,
              child: ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(12),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      launch.image.isNotEmpty ? launch.image : kRocketHeroImage,
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) =>
                          Container(color: Colors.grey[900]),
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.transparent, kPanelColor],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Right Details
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          launch.rocketName,
                          style: GoogleFonts.inter(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        CloseButton(
                          color: Colors.white,
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    Text(
                      launch.missionName,
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        color: kPrimaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      launch.company,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 14,
                        color: kTextMutedColor,
                      ),
                    ),

                    const SizedBox(height: 40),

                    Text(
                      "LAUNCH SPECS",
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white54,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _SpecRow(label: "STATUS", value: launch.status),
                    _SpecRow(label: "SITE", value: launch.site),
                    _SpecRow(label: "DATE", value: launch.dateDisplay),
                    // Mocked technical specs as they aren't in this API endpoint easily without secondary call
                    const _SpecRow(label: "STAGES", value: "2 (Est)"),
                    const _SpecRow(label: "PAYLOAD", value: "Classified / Var"),

                    const Spacer(),

                    ElevatedButton.icon(
                      onPressed: () {
                        launchUrl(
                          Uri.parse(
                            "https://en.wikipedia.org/wiki/${launch.rocketName}",
                          ),
                        );
                      },
                      icon: const Icon(Icons.search),
                      label: const Text("SEARCH WIKIPEDIA"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kCardColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          side: const BorderSide(color: kPrimaryColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpecRow extends StatelessWidget {
  final String label;
  final String value;
  const _SpecRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.jetBrainsMono(color: kTextMutedColor)),
          Flexible(
            child: Text(
              value,
              style: GoogleFonts.jetBrainsMono(color: Colors.white),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
