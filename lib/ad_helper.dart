import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdHelper {
  static String get appOpenAdUnitId {
    if (kDebugMode && Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/9257395921'; // Android App Open Test ID
    }
    return 'ca-app-pub-8573766407241910/8668799839';
  }

  static String get bannerAdUnitId {
    if (kDebugMode && Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/6300978111'; // Android Banner Test ID
    }
    return 'ca-app-pub-8573766407241910/6411291833';
  }

  static final AppOpenAdManager appOpenAdManager = AppOpenAdManager();

  static Future<void> initialize() async {
    await MobileAds.instance.initialize();
    appOpenAdManager.initialize();
  }
}

class AppOpenAdManager {
  AppOpenAd? _appOpenAd;
  bool _isShowingAd = false;
  bool _isLoadingAd = false;

  void initialize() {
    loadAd();
  }

  void dispose() {
    _appOpenAd?.dispose();
  }

  void loadAd() {
    if (_isLoadingAd || _appOpenAd != null) return;
    _isLoadingAd = true;
    
    AppOpenAd.load(
      adUnitId: AdHelper.appOpenAdUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenAd = ad;
          _isLoadingAd = false;
          debugPrint('AppOpenAd loaded successfully.');
        },
        onAdFailedToLoad: (error) {
          _isLoadingAd = false;
          debugPrint('AppOpenAd failed to load: $error');
        },
      ),
    );
  }

  void showAdIfAvailable({required VoidCallback onComplete}) {
    if (_isShowingAd) {
      debugPrint('AppOpenAd is already showing.');
      onComplete();
      return;
    }

    if (_appOpenAd == null) {
      debugPrint('AppOpenAd is not available.');
      onComplete();
      return;
    }

    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        _isShowingAd = true;
        debugPrint('AppOpenAd showed full screen content.');
      },
      onAdDismissedFullScreenContent: (ad) {
        _isShowingAd = false;
        ad.dispose();
        _appOpenAd = null;
        onComplete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _isShowingAd = false;
        ad.dispose();
        _appOpenAd = null;
        onComplete();
      },
    );

    _appOpenAd!.show();
  }
}

class BannerAdWidget extends StatefulWidget {
  final AdSize adSize;
  final bool showPlaceholder;

  const BannerAdWidget({
    super.key,
    this.adSize = AdSize.banner,
    this.showPlaceholder = true,
  });

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: AdHelper.bannerAdUnitId,
      size: widget.adSize,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() {
              _isLoaded = true;
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('BannerAd failed to load: $error');
          ad.dispose();
        },
      ),
    );
    _bannerAd!.load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _bannerAd == null) {
      if (!widget.showPlaceholder) {
        return const SizedBox.shrink();
      }
      return Container(
        height: widget.adSize.height.toDouble(),
        width: widget.adSize.width.toDouble(),
        alignment: Alignment.center,
        child: Text(
          'Ad',
          style: TextStyle(
            color: Colors.white30,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    return Container(
      alignment: Alignment.center,
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
