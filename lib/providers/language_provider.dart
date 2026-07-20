import 'package:flutter/material.dart';

class LanguageProvider extends ChangeNotifier {
  String _currentLanguage = 'en'; // default English

  String get currentLanguage => _currentLanguage;
  bool get isHindi => _currentLanguage == 'hi';

  void setLanguage(String langCode) {
    if (langCode == 'en' || langCode == 'hi') {
      _currentLanguage = langCode;
      notifyListeners();
    }
  }

  static const Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'admin_central': 'Admin Central',
      'clients_management': 'Clients Management',
      'data_ingestion': 'Data Ingestion',
      'factsheets_manager': 'Factsheets Manager',
      'invoice_signer': 'Invoice Signer',
      'settings': 'Settings',
      
      'clients_directory': 'Clients Directory',
      'data_ingestion_engine': 'Data Ingestion Engine',
      'settings_console': 'Settings Console',
      
      'display_settings': 'Display Settings',
      'display_settings_sub': 'Customize the application appearance to suit your preference.',
      'language_settings': 'Language Settings',
      'language_settings_sub': 'Choose your preferred language for the interface.',
      
      'time_range': 'Time Range',
      'nav_growth_trend': 'NAV Growth Trend',
      'recent_historical_navs': 'Recent Historical NAVs',
      'scheme_specifications': 'Scheme Specifications',
      'fund_facts_finder': 'Fund Facts Finder',
      'fund_facts_finder_sub': 'Type a mutual fund name to lookup its real-time scheme classification, ISIN codes, and historical NAV data.',
      'search_explore_factsheets': 'Search & Explore Fund Factsheets',
      'active_portfolio_holdings': 'Active Portfolio Holdings',
      'transaction_history': 'Transaction History',
      
      'total_invested': 'Total Invested',
      'current_valuation': 'Current Valuation',
      'absolute_return': 'Absolute Return',
      'annualized_return': 'Annualized Return (XIRR)',
      'investor_console': 'Investor Console',
      
      'refresh_data': 'Refresh Data',
      'logout': 'Logout',
      'search_funds_placeholder': 'Type 3+ characters to search funds (e.g. Axis Bluechip, SBI Liquid)...',
      'search_funds_placeholder_client': 'Enter at least 2 characters to search funds...',
      'no_fund_selected': 'No Fund Selected',
      'no_fund_selected_sub': 'Search and select a mutual fund to view its meta information and historical NAV data.',
      
      'light_mode': 'Light Mode',
      'light_mode_sub': 'Clean, light-hearted appearance',
      'dark_mode': 'Dark Mode',
      'dark_mode_sub': 'Classic deep space appearance',
      'system_preference': 'System Preference',
      'system_preference_sub': 'Automatically match device settings',
      'about_us': 'About Sharan Fincorp',
      'about_us_content': 'Sharan Fincorp deals in Mutual Funds with more than 15 years of experience, delivering the best customer experience in the market.',
      'contact_us': 'Contact Us',
      'portfolio': 'My Portfolio',
      'about_us_nav': 'About Us',
    },
    'hi': {
      'admin_central': 'एडमिन सेंट्रल',
      'clients_management': 'ग्राहक प्रबंधन',
      'data_ingestion': 'डेटा इनजेशन',
      'factsheets_manager': 'फैक्टशीट मैनेजर',
      'invoice_signer': 'इनवॉइस हस्ताक्षरकर्ता',
      'settings': 'सेटिंग्स',
      
      'clients_directory': 'ग्राहक निर्देशिका',
      'data_ingestion_engine': 'डेटा इनजेशन इंजन',
      'settings_console': 'सेटिंग्स कंसोल',
      
      'display_settings': 'प्रदर्शन सेटिंग्स',
      'display_settings_sub': 'अपनी पसंद के अनुसार एप्लिकेशन का स्वरूप कस्टमाइज़ करें।',
      'language_settings': 'भाषा सेटिंग्स',
      'language_settings_sub': 'इंटरफ़ेस के लिए अपनी पसंदीदा भाषा चुनें।',
      
      'time_range': 'समय सीमा',
      'nav_growth_trend': 'एनएवी विकास रुझान',
      'recent_historical_navs': 'हालिया ऐतिहासिक एनएवी',
      'scheme_specifications': 'योजना विनिर्देश',
      'fund_facts_finder': 'फंड फैक्ट्स फाइंडर',
      'fund_facts_finder_sub': 'रीयल-टाइम वर्गीकरण, आईएसआईएन कोड और ऐतिहासिक एनएवी डेटा देखने के लिए म्यूचुअल फंड का नाम टाइप करें।',
      'search_explore_factsheets': 'फंड फैक्टशीट खोजें और देखें',
      'active_portfolio_holdings': 'सक्रिय पोर्टफोलियो होल्डिंग्स',
      'transaction_history': 'लेनदेन इतिहास',
      
      'total_invested': 'कुल निवेश',
      'current_valuation': 'वर्तमान मूल्यांकन',
      'absolute_return': 'पूर्ण रिटर्न',
      'annualized_return': 'वार्षिक रिटर्न (XIRR)',
      'investor_console': 'निवेशक कंसोल',
      
      'refresh_data': 'डेटा रीफ्रेश करें',
      'logout': 'लॉगआउट',
      'search_funds_placeholder': 'फंड खोजने के लिए 3+ अक्षर टाइप करें (उदा. Axis Bluechip, SBI Liquid)...',
      'search_funds_placeholder_client': 'फंड खोजने के लिए कम से कम 2 अक्षर दर्ज करें...',
      'no_fund_selected': 'कोई फंड नहीं चुना गया',
      'no_fund_selected_sub': 'म्यूचुअल फंड की मेटा जानकारी और ऐतिहासिक एनएवी डेटा देखने के लिए खोजें और चुनें।',
      
      'light_mode': 'लाइट मोड',
      'light_mode_sub': 'साफ और हल्का स्वरूप',
      'dark_mode': 'डार्क मोड',
      'dark_mode_sub': 'क्लासिक डार्क स्पेस स्वरूप',
      'system_preference': 'सिस्टम वरीयता',
      'system_preference_sub': 'स्वचालित रूप से डिवाइस सेटिंग्स से मेल खाएं',
      'about_us': 'शरण फिनकॉर्प के बारे में',
      'about_us_content': 'शरण फिनकॉर्प म्यूचुअल फंड के क्षेत्र में 15 से अधिक वर्षों के अनुभव के साथ काम करता है, जो बाजार में सर्वोत्तम ग्राहक अनुभव प्रदान करता है।',
      'contact_us': 'संपर्क करें',
      'portfolio': 'मेरा पोर्टफोलियो',
      'about_us_nav': 'हमारे बारे में',
    }
  };

  String translate(String key) {
    return _localizedValues[_currentLanguage]?[key] ?? key;
  }
}
